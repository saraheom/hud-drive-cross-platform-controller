import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppState {
    let logger: LogManager
    let bluetooth: HudBluetoothManager
    let navigation: HudNavigationController
    let routeGuidance: RouteGuidanceAdapterClient
    let nowPlaying: CarPlayNowPlayingClient
    let obd: HudOBDController
    let speedEngine: OriginalSpeedLimitEngine
    let ambientLight: AmbientLightMonitor
    let settings = HudSettings()
    private(set) var externalCapture27: Any?
    private var musicFilterInitialized = false
    private var hudRehydrateTask: Task<Void, Never>?
    private var hudReassertTask: Task<Void, Never>?
    private var hudWiFiExposureTask: Task<Void, Never>?

    // v90.34.5 lane-presentation coordinator. The stock HUD auto-hides lane
    // graphics, so active lanes are reasserted while the selected policy says
    // they should remain visible. No HUD firmware write is involved.
    private var laneGuidanceRefreshTask: Task<Void, Never>?
    private var activeLaneGuidance: [HudCommands.NativeLane] = []
    private var activeLaneDistanceMeters = 0
    private var activeLaneContext = ""
    private let laneGuidanceRefreshInterval: Duration = .milliseconds(1500)

    // HUD Wi-Fi/AP exposure. This uses only stock BLE HUD-mode/hotspot packets;
    // it never sends the SoftwareUpdate start packet or any bytes to TCP/7980.
    private let hudWiFiRecoveryKey = "HUD.WiFiExposureRecoveryNeeded"
    private(set) var hudWiFiExposureActive = false
    private(set) var hudWiFiExposureStatus = "HUD Wi-Fi not forced"

    init() {
        let logger = LogManager()
        self.logger = logger
        let bluetooth = HudBluetoothManager(logger: logger)
        self.bluetooth = bluetooth
        let navigation = HudNavigationController(bluetooth: bluetooth, logger: logger)
        let showCurrentStreetKey = "HUD.Settings.navigationShowCurrentStreet"
        navigation.showCurrentStreet = UserDefaults.standard.object(forKey: showCurrentStreetKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: showCurrentStreetKey)
        self.navigation = navigation
        let routeGuidance = RouteGuidanceAdapterClient(logger: logger, navigation: navigation)
        self.routeGuidance = routeGuidance
        let nowPlaying = CarPlayNowPlayingClient(logger: logger)
        self.nowPlaying = nowPlaying
        let obd = HudOBDController(bluetooth: bluetooth, logger: logger)
        self.obd = obd
        routeGuidance.onWillActivate = { [weak obd] in
            obd?.applyNavigationWidgets()
        }
        let speedEngine = OriginalSpeedLimitEngine(bluetooth: bluetooth, logger: logger)
        self.speedEngine = speedEngine
        routeGuidance.onRoadContextChanged = { [weak speedEngine] context in
            speedEngine?.updateCarPlayRouteContext(context)
        }
        let ambientLight = AmbientLightMonitor(bluetooth: bluetooth, logger: logger)
        self.ambientLight = ambientLight
        if #available(iOS 27.0, *) {
            self.externalCapture27 = ExternalNavigationCapture(logger: logger, navigation: self.navigation)
        }

        if UserDefaults.standard.bool(forKey: hudWiFiRecoveryKey) {
            hudWiFiExposureStatus = "Wi-Fi release armed for next HUD BLE connection"
        }

        obd.onConnectionChanged = { [weak self, weak ambientLight] connected in
            // OBD remains useful telemetry/diagnostic state, but v90.29 no longer
            // uses it as permission for ambient animation. HUD transport readiness
            // is the reliable automatic-animation session gate.
            ambientLight?.obdPowerSignal(connected)
        }

        speedEngine.onSpeedStateChanged = { [weak ambientLight] speedMph, limitMph, available in
            ambientLight?.updateOverspeedWarning(
                gpsSpeedMph: speedMph,
                speedLimitMph: limitMph,
                limitAvailable: available
            )
        }

        nowPlaying.onTrackChanged = { [weak self] artist, track in
            self?.pushNowPlayingMetadataToHUD(artist: artist, track: track)
        }

        bluetooth.onTransportReady = { [weak self] in
            guard let self else { return }
            self.ambientLight.hudTransportPowerSignal(true)
            self.speedEngine.primeRectangularStyle()
            self.routeGuidance.start(reason: "HUD BLE transport ready")
            self.nowPlaying.start(reason: "HUD BLE transport ready")

            if UserDefaults.standard.bool(forKey: self.hudWiFiRecoveryKey),
               !self.hudWiFiExposureActive {
                self.disableHUDWiFiExposure(reason: "BLE transport recovery")
            }

            self.scheduleHUDRehydration(reason: "BLE transport ready")
        }

        bluetooth.onHUDSessionReset = { [weak self] in
            guard let self else { return }
            self.speedEngine.primeRectangularStyle()
            self.scheduleHUDRehydration(reason: "HUD firmware hello / physical session reset")
        }

        bluetooth.onTransportDisconnected = { [weak self] in
            guard let self else { return }
            // Ambient animation is gated by the actual HUD transport session.
            // Any HUD disconnect closes that gate; courtesy lights may remain on,
            // but automatic Breath waits for the next HUD transport connection.
            self.ambientLight.hudTransportPowerSignal(false)
            self.hudRehydrateTask?.cancel()
            self.hudRehydrateTask = nil
            self.hudReassertTask?.cancel()
            self.hudReassertTask = nil
            self.laneGuidanceRefreshTask?.cancel()
            self.laneGuidanceRefreshTask = nil
            self.hudWiFiExposureTask?.cancel()
            self.hudWiFiExposureTask = nil
            if self.hudWiFiExposureActive {
                self.hudWiFiExposureActive = false
                self.hudWiFiExposureStatus = "BLE lost — Wi-Fi release armed for reconnect"
                UserDefaults.standard.set(true, forKey: self.hudWiFiRecoveryKey)
            }
            self.obd.transportDisconnected()
            self.routeGuidance.stop(reason: "HUD BLE transport disconnected")
            self.nowPlaying.stop(reason: "HUD BLE transport disconnected")
            self.logger.log(
                "HUD SESSION",
                "BLE transport disconnected; Route Guidance polling stopped and HUD returned to Freeride"
            )
        }

    }

    /// The original HUDWAY protocol separates dashboard profile configuration
    /// (`HudWidgetCommandPacket`, type 0/1) from the active Navigation/Freeride
    /// mode (`navigationState`). Rehydrating both profiles must therefore finish by
    /// restoring the actual active mode; otherwise a firmware/session reset can
    /// leave the HUD center presentation in the wrong state even though the
    /// Freeride type-0 profile itself is correct.
    private func restoreDashboardOperatingMode(reason: String) {
        guard bluetooth.state == .connected else { return }
        if navigation.navigationActive {
            bluetooth.enqueue(
                HudCommands.navigationState(true),
                label: "Restore dashboard mode → Navigation ON"
            )
            // The CarPlay adapter feed owns maneuver re-delivery. Do not
            // fabricate/resend the controller's default instruction.
            logger.log("DASHBOARD MODE", "Restored Navigation ON after profile rehydration reason=\(reason)")
        } else {
            bluetooth.enqueue(
                HudCommands.navigationState(false),
                label: "Restore dashboard mode → Freeride (Navigation OFF)"
            )
            logger.log(
                "DASHBOARD MODE",
                "Restored original Freeride active mode via Navigation OFF after profile rehydration reason=\(reason)"
            )
        }
    }


    func initializeHUD() {
        logger.log("APP", "Initialize HUD requested")
        bluetooth.initializeHUD()
    }

    /// Persistent top-bar shortcut for adapter-only CarPlay Route Guidance.
    /// It never starts ScreenCaptureKit and never forces Navigation ON without
    /// a fresh active adapter route. If the feed is absent, HUD remains Freeride.
    func quickStartNavigation() {
        logger.log("QUICK ACTION", "Navigation shortcut tapped — adapter-only Route Guidance refresh")
        routeGuidance.start(reason: "Navigation shortcut")
        routeGuidance.refreshNow()
    }

    /// Persistent top-bar shortcut: refresh the passive CarPlay Now Playing feed.
    /// No media-app authorization or app switching is required.
    func quickRefreshNowPlaying() {
        logger.log("QUICK ACTION", "Music shortcut tapped — CarPlay Now Playing refresh")
        nowPlaying.refreshNow()
    }

    func applyBrightness() {
        // v90.16: when ambient headlight automation owns HUD Auto Brightness,
        // do not let the generic persisted HUD setting fight that consensus during
        // rehydration or a settings refresh. rehydrateHUDState()/headlight edges
        // are the single owner until the ambient trigger is disabled.
        if ambientLight.enabled && ambientLight.hudBrightnessTriggerEnabled {
            logger.log(
                "HUD BRIGHTNESS",
                "Generic brightness apply deferred — ambient headlight consensus owns HUD Auto Brightness"
            )
            return
        }

        bluetooth.enqueue(HudCommands.autoBrightness(settings.autoBrightness), label: "Auto brightness \(settings.autoBrightness)")
        if !settings.autoBrightness {
            bluetooth.enqueue(HudCommands.manualBrightness(settings.brightness), label: "Brightness \(settings.brightness)")
        }
    }

    func applyTimeWeather() {
        bluetooth.enqueue(HudCommands.timeWeather(settings.showTimeWeather), label: "Time/weather \(settings.showTimeWeather)")
    }


    func applyColorTheme() {
        bluetooth.enqueue(
            HudCommands.baseColor(settings.colorTheme),
            label: "HUD color theme \(settings.colorTheme.rawValue) \(settings.colorTheme.originalWireValue)"
        )
        logger.log(
            "HUD COLOR",
            "Applied \(settings.colorTheme.rawValue) raw=\(settings.colorTheme.originalWireValue)"
        )
    }


    func applyNotificationSettings() {
        logger.log("NOTIFICATION", "Applying HUD ANCS notification filter settings")

        bluetooth.enqueue(
            HudCommands.notificationSettingsInit(),
            label: "Notification filter init"
        )
        bluetooth.enqueue(
            HudCommands.notificationsMasterEnabled(true),
            label: "Notifications master ON"
        )
        bluetooth.enqueue(
            HudCommands.notificationTimeout(seconds: settings.notificationExposureSeconds),
            label: "Notification timeout \(settings.notificationExposureSeconds)s"
        )
        bluetooth.enqueue(
            HudCommands.notificationLineCount(settings.notificationLines),
            label: "Notification lines \(settings.notificationLines)"
        )

        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: settings.notifyMusic),
            label: "Music notification popups \(settings.notifyMusic ? "ON" : "OFF")"
        )
        musicFilterInitialized = settings.notifyMusic

        if settings.notifyAll {
            logger.log("NOTIFICATION", "All notifications mode enabled")
            return
        }

        let selections: [(HudNotificationKind, Bool)] = [
            (.calls, settings.notifyCalls),
            (.messages, settings.notifyMessages),
            (.calendar, settings.notifyCalendar),
            (.gmail, settings.notifyGmail),
            (.weChat, settings.notifyWeChat),
            (.kakaoTalk, settings.notifyKakaoTalk)
        ]

        for (kind, enabled) in selections where enabled {
            logger.log(
                "NOTIFICATION FILTER",
                "\(kind.displayName): \(kind.identifiers.joined(separator: ", "))"
            )
            bluetooth.enqueue(
                HudCommands.notificationFilter(
                    enabled: true,
                    textColor: kind.textColor,
                    icon: kind.hudIcon,
                    identifiers: kind.identifiers
                ),
                label: "Notification filter \(kind.displayName)"
            )
        }
    }

    func applyDashboardPreset() {
        let p = settings.selectedPreset
        if p.name == "Freeride" {
            // The original HUDWAY Freeride mode is the type=0 dashboard packet
            // with center=Simple and user-selectable side widgets. Route the
            // generic Dashboard preset through that exact implementation so the
            // Dashboard screen cannot replace the original center RPM/bar UI with
            // the older approximation (`center=Speedo`).
            obd.applyFreerideWidgets()
            logger.log("DASHBOARD", "Freeride preset routed to original type=0 center=Simple implementation")
            return
        }
        bluetooth.enqueue(
            HudCommands.dashboard(left: p.left, center: p.center, right: p.right, navigationLayout: p.navigationLayout),
            label: "Dashboard \(p.name)"
        )
    }



    // MARK: - Navigation presentation / lane guidance

    var laneGuidanceThresholdMeters: Int {
        Int((settings.laneGuidanceDistanceMiles * 1609.344).rounded())
    }

    func applyNavigationPresentationSettings() {
        navigation.showCurrentStreet = settings.navigationShowCurrentStreet
        logger.log(
            "NAV PRESENTATION",
            "currentStreet=\(settings.navigationShowCurrentStreet ? "ON" : "OFF") lanes=\(settings.laneGuidanceMode.title) threshold=\(String(format: "%.1f", settings.laneGuidanceDistanceMiles))mi"
        )

        // Re-send the currently visible maneuver so the current-street toggle is
        // immediately observable during parked replay and normal navigation.
        if bluetooth.state == .connected, navigation.navigationActive {
            navigation.sendCurrent(owner: navigation.feedOwner)
        }
        reevaluateActiveLaneGuidance(reason: "settings changed")
    }

    private func shouldDisplayActiveLanes() -> Bool {
        guard !activeLaneGuidance.isEmpty else { return false }
        switch settings.laneGuidanceMode {
        case .off:
            return false
        case .persistent:
            return true
        case .nearTurn:
            return activeLaneDistanceMeters <= laneGuidanceThresholdMeters
        }
    }

    private func reevaluateActiveLaneGuidance(reason: String) {
        laneGuidanceRefreshTask?.cancel()
        laneGuidanceRefreshTask = nil

        guard bluetooth.state == .connected else { return }
        guard shouldDisplayActiveLanes() else {
            bluetooth.enqueue(HudCommands.clearLaneGuidance(), label: "Lane policy → clear (\(reason))")
            logger.log(
                "HUD LANE POLICY",
                "hidden reason=\(reason) mode=\(settings.laneGuidanceMode.title) distance=\(activeLaneDistanceMeters)m threshold=\(laneGuidanceThresholdMeters)m"
            )
            return
        }

        sendActiveLaneGuidance(label: "Lane policy → show (\(reason))")
        laneGuidanceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.laneGuidanceRefreshInterval)
                guard !Task.isCancelled,
                      self.bluetooth.state == .connected,
                      self.navigation.navigationActive,
                      self.shouldDisplayActiveLanes() else { break }
                self.sendActiveLaneGuidance(label: "Lane policy → persistence refresh")
            }
        }
    }

    private func sendActiveLaneGuidance(label: String) {
        bluetooth.enqueue(HudCommands.laneGuidance(activeLaneGuidance), label: label)
        logger.log(
            "HUD LANE POLICY",
            "show context=\(activeLaneContext) mode=\(settings.laneGuidanceMode.title) distance=\(activeLaneDistanceMeters)m values=\(activeLaneGuidance.map { String($0.wireValue) }.joined(separator: ","))"
        )
    }

    func setLaneGuidanceForCurrentManeuver(
        _ lanes: [HudCommands.NativeLane],
        distanceMeters: Int,
        context: String
    ) {
        activeLaneGuidance = lanes
        activeLaneDistanceMeters = max(0, distanceMeters)
        activeLaneContext = context
        reevaluateActiveLaneGuidance(reason: "new lane data")
    }

    func clearLaneGuidancePolicy(reason: String = "manual clear") {
        laneGuidanceRefreshTask?.cancel()
        laneGuidanceRefreshTask = nil
        activeLaneGuidance = []
        activeLaneDistanceMeters = 0
        activeLaneContext = ""
        guard bluetooth.state == .connected else { return }
        bluetooth.enqueue(HudCommands.clearLaneGuidance(), label: "Lane guidance clear")
        logger.log("HUD LANE POLICY", "clear reason=\(reason)")
    }

    // MARK: - HUD Wi-Fi / casting network exposure

    var hudWiFiExpectedSSID: String {
        bluetooth.connectedName ?? bluetooth.savedHUDName ?? "HUDWAY Drive"
    }

    func enableHUDWiFiExposure() {
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "Connect the HUD over BLE first"
            return
        }

        hudWiFiExposureTask?.cancel()
        hudWiFiExposureActive = true
        hudWiFiExposureStatus = "Starting iOS HUDWAY AP…"
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)

        // HudLauncher firmware modes recovered from KivicModeCommandPacket:
        // 4 = IOS_HUD_MODE, 5 = IOS_KIVICCAST_MODE.
        // Mode 5 is the path that runs doIOSKiviccastNow / SoftAP setup. We
        // briefly enter it to initialize hostapd/dnsmasq, then return to mode 4
        // while keeping HudHotspotBaseband forceEnable asserted so the local
        // HUD renderer (navigation/lanes) remains usable. No firmware write.
        logger.log(
            "HUD WIFI",
            "Enable 2.4GHz HUD AP: force hotspot ON → IOS_KIVICCAST_MODE(5) bootstrap → IOS_HUD_MODE(4); no SoftwareUpdate/TCP firmware transfer"
        )

        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: false, forceEnable: true),
            label: "HUD Wi-Fi → force 2.4GHz AP ON"
        )

        hudWiFiExposureTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, self.hudWiFiExposureActive,
                  self.bluetooth.state == .connected else { return }

            self.bluetooth.enqueue(
                HudCommands.kivicMode(5),
                label: "HUD Wi-Fi → iOS KivicCast bootstrap mode 5"
            )
            self.bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → bootstrap KeepAlive")
            self.hudWiFiExposureStatus = "Initializing HUDWAY DHCP/AP…"

            // Give the old Android 5.1 firmware time to run the iOS KivicCast
            // SoftAP path before restoring the normal iOS HUD renderer.
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, self.hudWiFiExposureActive,
                  self.bluetooth.state == .connected else { return }

            self.bluetooth.enqueue(
                HudCommands.kivicMode(4),
                label: "HUD Wi-Fi → return iOS HUD mode 4 (AP remains forced)"
            )
            self.bluetooth.enqueue(HudCommands.fullScreen(true), label: "HUD Wi-Fi → native HUD full screen")
            self.bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → final KeepAlive")
            self.hudWiFiExposureStatus = "HUD Wi-Fi exposed — join SSID, then test 192.168.43.1"
            self.hudWiFiExposureTask = nil
        }
    }

    /// Diagnostic fallback: keep the firmware in IOS_KIVICCAST_MODE(5) instead
    /// of returning to IOS_HUD_MODE(4). Useful only to determine whether mode 4
    /// tears the AP down on this firmware. The local HUD renderer may be hidden
    /// while this is active. Still BLE-only and performs no firmware write.
    func holdHUDWiFiCastingModeForDiagnostics() {
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "Connect the HUD over BLE first"
            return
        }
        hudWiFiExposureTask?.cancel()
        hudWiFiExposureTask = nil
        hudWiFiExposureActive = true
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)
        logger.log("HUD WIFI", "Diagnostic: hold IOS_KIVICCAST_MODE(5) with 2.4GHz hotspot forced ON")
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: false, forceEnable: true),
            label: "HUD Wi-Fi diagnostic → force 2.4GHz AP ON"
        )
        bluetooth.enqueue(HudCommands.kivicMode(5), label: "HUD Wi-Fi diagnostic → hold iOS KivicCast mode 5")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi diagnostic → KeepAlive")
        hudWiFiExposureStatus = "Diagnostic casting mode 5 held — check DHCP/192.168.43.1"
    }

    /// Return to the normal iOS HUD renderer without releasing the forced AP.
    /// This lets a stationary test determine whether the AP survives mode 5→4.
    func returnHUDRendererKeepingWiFi() {
        guard bluetooth.state == .connected, hudWiFiExposureActive else { return }
        hudWiFiExposureTask?.cancel()
        hudWiFiExposureTask = nil
        logger.log("HUD WIFI", "Diagnostic: return IOS_HUD_MODE(4) while keeping forced AP")
        bluetooth.enqueue(HudCommands.kivicMode(4), label: "HUD Wi-Fi diagnostic → return iOS HUD mode 4")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "HUD Wi-Fi diagnostic → native HUD full screen")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi diagnostic → KeepAlive")
        hudWiFiExposureStatus = "iOS HUD mode 4 restored — AP still requested"
    }

    func disableHUDWiFiExposure(reason: String = "manual") {
        hudWiFiExposureTask?.cancel()
        hudWiFiExposureTask = nil
        hudWiFiExposureActive = false
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "HUD disconnected — Wi-Fi release armed for reconnect"
            UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)
            return
        }
        logger.log("HUD WIFI", "Disable forced HUD AP reason=\(reason); restore IOS_HUD_MODE(4)")
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: false, forceEnable: false),
            label: "HUD Wi-Fi → release forced AP"
        )
        bluetooth.enqueue(HudCommands.kivicMode(4), label: "HUD Wi-Fi → restore iOS HUD mode 4")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "HUD Wi-Fi → full screen ON")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → KeepAlive")
        UserDefaults.standard.set(false, forKey: hudWiFiRecoveryKey)
        hudWiFiExposureStatus = "HUD Wi-Fi force released"
    }


    enum NativeLaneTestPreset: String, CaseIterable, Identifiable {
        case fourStraightUseThird
        case fourStraightUseMiddleTwo
        case fourMixedUseLeftTurn
        case fourMixedUseRightBranch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fourStraightUseThird:
                return "4 straight • use lane 3"
            case .fourStraightUseMiddleTwo:
                return "4 straight • use lanes 2–3"
            case .fourMixedUseLeftTurn:
                return "4 mixed • use straight+left"
            case .fourMixedUseRightBranch:
                return "4 mixed • use straight+right"
            }
        }

        var lanes: [HudCommands.NativeLane] {
            switch self {
            case .fourStraightUseThird:
                return [
                    .init(type: .straight, recommended: false),
                    .init(type: .straight, recommended: false),
                    .init(type: .straight, recommended: true),
                    .init(type: .straight, recommended: false),
                ]
            case .fourStraightUseMiddleTwo:
                return [
                    .init(type: .straight, recommended: false),
                    .init(type: .straight, recommended: true),
                    .init(type: .straight, recommended: true),
                    .init(type: .straight, recommended: false),
                ]
            case .fourMixedUseLeftTurn:
                return [
                    .init(type: .left, recommended: false),
                    .init(type: .straightLeft, recommended: true),
                    .init(type: .straight, recommended: false),
                    .init(type: .right, recommended: false),
                ]
            case .fourMixedUseRightBranch:
                return [
                    .init(type: .left, recommended: false),
                    .init(type: .straight, recommended: false),
                    .init(type: .straightRight, recommended: true),
                    .init(type: .right, recommended: false),
                ]
            }
        }
    }

    func sendNativeLaneTest(_ preset: NativeLaneTestPreset) {
        guard bluetooth.state == .connected else { return }
        bluetooth.enqueue(
            HudCommands.laneGuidance(preset.lanes),
            label: "Native lane test → \(preset.title)"
        )
        logger.log(
            "HUD NATIVE LANES",
            "preset=\(preset.title) values=\(preset.lanes.map { String($0.wireValue) }.joined(separator: ","))"
        )
    }

    func clearNativeLaneTest() {
        clearLaneGuidancePolicy(reason: "native/replay test clear")
        logger.log("HUD NATIVE LANES", "clear")
    }

    func sendRecordedCarPlayLaneReplayStep(_ step: RecordedCarPlayLaneReplay.Step) {
        guard bluetooth.state == .connected else { return }

        // Parked diagnostic replay: send the captured maneuver through the same
        // native HUDWAY path, immediately followed by the captured 0x5204 lane
        // topology normalized to HudLanesManueverCommandPacket values.
        navigation.showCurrentStreet = settings.navigationShowCurrentStreet
        navigation.navigationOn()
        navigation.send(step.instruction)
        setLaneGuidanceForCurrentManeuver(
            step.nativeLanes,
            distanceMeters: step.instruction.distanceMeters,
            context: "Recorded \(step.source) rec \(step.captureRecord) group \(step.laneGroupIndex)"
        )
        logger.log(
            "HUD LANE REPLAY",
            "source=\(step.source) rec=\(step.captureRecord) group=\(step.laneGroupIndex) road=\(step.currentRoad) maneuver=\(step.maneuverDescription) angles=\(step.laneAngleSummary) hud=\(step.hudValueSummary)"
        )
    }

    func sendNativeMusicMiniTest(artist: String? = nil, track: String? = nil) {
        guard bluetooth.state == .connected else { return }

        let resolvedArtist = artist ?? (nowPlaying.artist.isEmpty ? "Kenshi Yonezu" : nowPlaying.artist)
        let resolvedTrack = track ?? (nowPlaying.title == "No CarPlay media" ? "Flamingo" : nowPlaying.title)

        // Diagnostic-only firmware-native path. These are BLE commands only:
        // no ADB, filesystem, updater, or firmware writes are involved.
        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: true),
            label: "Mini music test → native filter ON"
        )
        bluetooth.enqueue(
            HudCommands.widgetsMiniState(true),
            label: "Mini music test → HUD mini state ON"
        )
        bluetooth.enqueue(
            HudCommands.musicNotification(
                artist: resolvedArtist,
                track: resolvedTrack
            ),
            label: "Mini music test → \(resolvedArtist) — \(resolvedTrack)"
        )
        logger.log("HUD MINI MUSIC", "enabled artist=\(resolvedArtist) track=\(resolvedTrack)")
    }

    func restoreFromNativeMusicMiniTest() {
        guard bluetooth.state == .connected else { return }
        bluetooth.enqueue(
            HudCommands.widgetsMiniState(false),
            label: "Mini music test → HUD mini state OFF"
        )
        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: settings.notifyMusic),
            label: "Mini music test → restore Music filter \(settings.notifyMusic ? "ON" : "OFF")"
        )
        musicFilterInitialized = settings.notifyMusic
        logger.log("HUD MINI MUSIC", "restored normal state")
    }


    func sendNativeMusicTest() {
        pushNowPlayingMetadataToHUD(
            artist: nowPlaying.artist.isEmpty ? "Kenshi Yonezu" : nowPlaying.artist,
            track: nowPlaying.title == "No CarPlay media" ? "Flamingo" : nowPlaying.title
        )
    }


    func pushNowPlayingMetadataToHUD(artist: String? = nil, track: String? = nil) {
        guard bluetooth.state == .connected else { return }

        let resolvedArtist = artist ?? nowPlaying.artist
        let resolvedTrack = track ?? nowPlaying.title
        guard !resolvedArtist.isEmpty,
              !resolvedTrack.isEmpty,
              resolvedTrack != "No CarPlay media" else { return }

        guard settings.notifyMusic else {
            if musicFilterInitialized {
                musicFilterInitialized = false
                bluetooth.enqueue(
                    HudCommands.musicNotificationFilter(enabled: false),
                    label: "Disable native Music notification filter"
                )
            }
            return
        }

        if !musicFilterInitialized {
            musicFilterInitialized = true
            bluetooth.enqueue(
                HudCommands.musicNotificationFilter(enabled: true),
                label: "Enable native Music notification filter"
            )
        }

        bluetooth.enqueue(
            HudCommands.musicNotification(
                artist: resolvedArtist,
                track: resolvedTrack
            ),
            label: "Native music: \(resolvedArtist) — \(resolvedTrack)"
        )

    }


    private func scheduleHUDRehydration(reason: String) {
        hudRehydrateTask?.cancel()
        hudReassertTask?.cancel()

        hudRehydrateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Phase 1: establish only base transport/session state promptly.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, self.bluetooth.state == .connected else { return }
            self.rehydrateBaseHUD(reason: reason)

            // Phase 2: let the physical HUD firmware finish loading defaults,
            // then overwrite every persisted user-visible setting.
            try? await Task.sleep(for: .milliseconds(1650))
            guard !Task.isCancelled, self.bluetooth.state == .connected else { return }
            self.rehydrateUserHUD(reason: reason)

            // Phase 3: firmware has previously re-applied defaults after our
            // first packets. Reassert display-critical state once more.
            self.hudReassertTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled,
                      self.bluetooth.state == .connected else { return }
                self.reassertDisplayCriticalState(reason: reason)
                self.hudReassertTask = nil
            }

            self.hudRehydrateTask = nil
        }
    }

    private func rehydrateBaseHUD(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 1 base BEGIN reason=\(reason)")
        bluetooth.enqueue(HudCommands.systemTime(), label: "Rehydrate → system time")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "Rehydrate → keep alive")
        bluetooth.enqueue(HudCommands.phoneName(UIDevice.current.name), label: "Rehydrate → phone name")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "Rehydrate → full screen")
        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Rehydrate → imperial units (mi/mph)")
        speedEngine.primeRectangularStyle()
        logger.log("HUD REHYDRATE", "PHASE 1 base END")
    }

    private func rehydrateUserHUD(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 2 persisted state BEGIN")

        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Persisted units → imperial (mi/mph)")
        applyBrightness()
        applyTimeWeather()
        applyColorTheme()
        applyNotificationSettings()
        obd.hudDidBecomeReady()
        restoreDashboardOperatingMode(reason: "phase 2 persisted state / \(reason)")
        ambientLight.rehydrateHUDState()
        speedEngine.primeRectangularStyle()
        speedEngine.rehydrateHUDState()


        musicFilterInitialized = false
        pushNowPlayingMetadataToHUD()

        logger.log(
            "HUD REHYDRATE",
            "PHASE 2 END brightness=\(settings.brightness) autoBrightness=\(settings.autoBrightness) " +
            "timeWeather=\(settings.showTimeWeather) color=\(settings.colorTheme.rawValue) OBDauto=\(obd.autoConnect) " +
            "speedLimit=\(speedEngine.showSpeedLimit) warning=original-auto"
        )
    }

    private func reassertDisplayCriticalState(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 3 display reassert BEGIN reason=\(reason)")

        // These are deliberately resent after firmware startup so the HUD's
        // own boot defaults cannot win. Rectangular speed-limit style is
        // hard-coded inside the speed engine/command path.
        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Reassert → imperial units (mi/mph)")
        applyBrightness()
        applyColorTheme()
        applyTimeWeather()
        obd.applyWidgetSelection()
        restoreDashboardOperatingMode(reason: "phase 3 display reassert / \(reason)")
        ambientLight.rehydrateHUDState()
        speedEngine.rehydrateHUDState()


        logger.log("HUD REHYDRATE", "PHASE 3 display reassert END")
    }

}