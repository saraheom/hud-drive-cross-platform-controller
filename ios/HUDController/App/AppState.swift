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
    let maintenance: HudMaintenanceManager
    let settings = HudSettings()
    let mapModeSettings = HudMapModeSettings()
    let mapModeCastServer = HudMapModeCastServer()
    let mainVideo: U2WMainVideoClient
    let hudU2WFrameRelay: U2WHUDFrameRelayClient
    private var mapModeFrameTask: Task<Void, Never>?
    private var mapModeOBDOverlayTask: Task<Void, Never>?
    private var mapModeFrozenSnapshot: HudMapModeSnapshot?
    private var mapModeFrozenSourceImage: UIImage?
    private(set) var mapModeActive = false
    private(set) var mapModeStatus = "Map Mode off"
    private(set) var mapModeLastNetworkEvent = "Cast server idle"
    private(set) var hudU2WSTAStatus = "Not tested"
    private(set) var hudU2WSTAAddress = ""
    private(set) var hudU2WSTAReason = ""
    private(set) var hudU2WSTAConnected = false
    private var hudU2WSTAStatusTask: Task<Void, Never>?
    private var hudU2WRelayFrameTask: Task<Void, Never>?
    private var hudU2WKivicKickTask: Task<Void, Never>?
    private var hudU2WKivicKickCount = 0
    private var hudU2WLastManualDisplayRetryAt = Date.distantPast
    private var hudU2WSTAResetInProgress = false
    private var hudU2WIgnoreEmptyStatusUntil = Date.distantPast
    private(set) var hudU2WLiveRelayActive = false
    private(set) var externalCapture27: Any?
    private var musicFilterInitialized = false
    private var hudRehydrateTask: Task<Void, Never>?
    private var hudReassertTask: Task<Void, Never>?
    private var hudWiFiExposureTask: Task<Void, Never>?
    private var firmwareMaintenanceTask: Task<Void, Never>?
    private var displayScaleApplyTask: Task<Void, Never>?
    private var displayPerspectiveApplyTask: Task<Void, Never>?
    private var timeWeatherPostDashboardTask: Task<Void, Never>?
    private var timeWeatherColdOffSyncTask: Task<Void, Never>?

    // v90.34.9 persistent stock-music experiment. Static inspection of the
    // HUDWAY Drive launcher shows MusicNotificationPacket is consumed directly
    // by MainActivity and fed into the stock full/mini music views; there is no
    // public broadcast carrying the parsed metadata. The least-invasive way to
    // test persistence is therefore to reassert the existing native music packet
    // before the launcher's shared notification timeout expires.
    private var persistentMusicTask: Task<Void, Never>?
    private(set) var persistentMusicActive = false
    private(set) var persistentMusicMini = false
    private(set) var persistentMusicStatus = "Persistent music stopped"
    private let persistentMusicRefreshInterval: Duration = .seconds(5)

    // v90.34.5 lane-presentation coordinator. The stock HUD auto-hides lane
    // graphics, so active lanes are reasserted while the selected policy says
    // they should remain visible. No HUD firmware write is involved.
    private var laneGuidanceRefreshTask: Task<Void, Never>?
    private var activeLaneGuidance: [HudCommands.NativeLane] = []
    private var activeLaneDistanceMeters = 0
    private var activeLaneContext = ""
    private var activeLaneIsLive = false
    private var activeLiveLaneManeuverIndex: Int?
    private var activeLiveLaneGuidanceIndex: Int?
    private var activeLiveLaneEventIndex: Int?
    private let laneGuidanceRefreshInterval: Duration = .milliseconds(1500)
    // v90.34.10: safe stock-widget probe for the user's requested right-side
    // lane placement. No firmware/APK write is performed. While active we
    // temporarily replace the normal Navigation dashboard with an isolated
    // side-widget factory probe so a lane packet can reveal whether the stock
    // launcher has any hidden right-side lane-capable renderer.
    private var laneRightSideProbeActive = false
    private var laneRightSideProbeWidget: String?

    // Legacy U2W v8.7 fallback cache. v8.7 incorrectly labeled the 0x5204
    // composed-guidance-event id as a route maneuver index and retained only the
    // last event in a pre-cache burst. U2W v8.8 does not use this cache: it
    // resolves the active event on the adapter via 0x5201 InfoType 16.
    private struct LiveLaneCacheEntry: Equatable {
        var laneSequence: Int
        var lanes: [HudCommands.NativeLane]
        var rawSummary: String
    }
    private var liveLaneCacheByManeuver: [Int: LiveLaneCacheEntry] = [:]
    private var liveLaneCurrentManeuverIndex: Int?
    private var liveLaneSource: String?
    private var liveLaneLastRouteState: Int?
    private var liveLaneSessionActive = false
    private var loggedLegacyV87LaneSchema = false

    // HUD Wi-Fi/AP exposure. This uses only stock BLE HUD-mode/hotspot packets;
    // it never sends the SoftwareUpdate start packet or any bytes to TCP/7980.
    private let hudWiFiRecoveryKey = "HUD.WiFiExposureRecoveryNeeded"
    private(set) var hudWiFiExposureActive = false
    private(set) var hudWiFiExposureStatus = "HUD Wi-Fi not forced"
    private(set) var firmwareMaintenanceActive = false

    init() {
        let logger = LogManager()
        self.logger = logger
        let mainVideo = U2WMainVideoClient(logger: logger)
        self.mainVideo = mainVideo
        let hudU2WFrameRelay = U2WHUDFrameRelayClient(logger: logger)
        self.hudU2WFrameRelay = hudU2WFrameRelay
        let maintenance = HudMaintenanceManager(logger: logger)
        self.maintenance = maintenance
        let bluetooth = HudBluetoothManager(logger: logger)
        self.bluetooth = bluetooth
        let navigation = HudNavigationController(bluetooth: bluetooth, logger: logger)
        let showCurrentStreetKey = "HUD.Settings.navigationShowCurrentStreet"
        navigation.showCurrentStreet = UserDefaults.standard.object(forKey: showCurrentStreetKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: showCurrentStreetKey)
        let showCurrentTurnTextKey = "HUD.Settings.navigationShowCurrentTurnText"
        navigation.showCurrentTurnText = UserDefaults.standard.object(forKey: showCurrentTurnTextKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: showCurrentTurnTextKey)
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
        navigation.onNavigationModeChanged = { [weak speedEngine] active in
            // The stock HUD can instantiate a fresh gauge renderer when the
            // active dashboard mode changes. Re-send the original HUDWAY
            // DisplaySpeedWarning threshold shortly afterward so the stock
            // warning state is available to a fresh Freeride Simple or Navigation
            // Speedo renderer. Physical red-arc ownership remains under test.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                speedEngine?.reassertOriginalSpeedMarker(
                    reason: active ? "Navigation renderer activated" : "Freeride renderer activated"
                )
            }
        }
        routeGuidance.onRoadContextChanged = { [weak speedEngine] context in
            speedEngine?.updateCarPlayRouteContext(context)
        }
        let ambientLight = AmbientLightMonitor(bluetooth: bluetooth, logger: logger)
        self.ambientLight = ambientLight
        obd.onDashboardProfileApplied = { [weak self] profile in
            self?.scheduleTimeWeatherPostDashboardReassert(reason: "\(profile) dashboard profile applied")
        }
        routeGuidance.onLaneGuidanceChanged = { [weak self] state in
            self?.receiveLiveLaneGuidance(state)
        }
        routeGuidance.onManeuverDelivered = { [weak self] maneuverIndex in
            self?.reassertLiveLaneAfterManeuverDelivery(maneuverIndex: maneuverIndex)
        }
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
            if connected, self?.mapModeActive == true {
                self?.startNativeOBDSpeedOverlayProbeIfNeeded()
            }
        }

        bluetooth.onWiFiSTAStatusEvent = { [weak self] status, reason, address in
            guard let self else { return }

            // Field evidence from v90.35.3.4: the HUD can report stock status=6
            // ("Empty network") while simultaneously returning a valid DHCP address
            // such as 192.168.50.100. U2W's ARP table also shows that peer. Therefore
            // status=6 is not a reliable link-layer disconnect signal on this firmware.
            // Treat a valid IPv4 address as a "soft connected" STA link and continue
            // to the KivicCast viewer/discovery stage instead of waiting forever for
            // status=1. Status=1 remains the definitive positive state.
            let hasAddress = self.isUsableHUDSTAAddress(address)
            let linkUp = status == 1 || (self.hudU2WLiveRelayActive && hasAddress && status == 6)

            self.hudU2WSTAConnected = linkUp
            if !address.isEmpty {
                self.hudU2WSTAAddress = address
            }
            self.hudU2WSTAReason = reason

            switch status {
            case 1:
                self.hudU2WSTAStatus = self.hudU2WLiveRelayActive ? "Wi-Fi connected — starting HUD display…" : "Connected"
            case 2:
                self.hudU2WSTAStatus = "Disconnected"
            case 3:
                self.hudU2WSTAStatus = "HUD requested hotspot"
            case 4:
                self.hudU2WSTAStatus = "Address search timeout"
            case 5:
                self.hudU2WSTAStatus = "Invalid network info"
            case 6 where linkUp:
                self.hudU2WSTAStatus = "Wi-Fi IP acquired — starting HUD display…"
            case 6:
                self.hudU2WSTAStatus = "Joining U2W Wi-Fi…"
            default:
                self.hudU2WSTAStatus = "Status \(status)"
            }

            if self.hudU2WLiveRelayActive, linkUp, self.hudU2WKivicKickCount == 0 {
                self.primeHUDU2WKivicViewer(
                    reason: status == 1 ? "STA status=1 connected" : "STA has DHCP address despite status=6"
                )
            }

            self.logger.log(
                "HUD/U2W STA",
                "event status=\(status) linkUp=\(linkUp) address=\(address.isEmpty ? "—" : address) reason=\(reason.isEmpty ? "—" : reason)"
            )
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
            self.mainVideo.start(reason: "HUD BLE transport ready")

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
            self.timeWeatherPostDashboardTask?.cancel()
            self.timeWeatherPostDashboardTask = nil
            self.timeWeatherColdOffSyncTask?.cancel()
            self.timeWeatherColdOffSyncTask = nil
            self.hudU2WSTAStatusTask?.cancel()
            self.hudU2WSTAStatusTask = nil
            self.hudU2WRelayFrameTask?.cancel()
            self.hudU2WRelayFrameTask = nil
            self.hudU2WFrameRelay.stop(reason: "HUD BLE transport disconnected")
            self.hudU2WLiveRelayActive = false
            self.hudU2WSTAConnected = false
            self.laneGuidanceRefreshTask?.cancel()
            self.laneGuidanceRefreshTask = nil
            self.laneRightSideProbeActive = false
            self.laneRightSideProbeWidget = nil
            self.hudWiFiExposureTask?.cancel()
            self.hudWiFiExposureTask = nil
            self.firmwareMaintenanceTask?.cancel()
            self.firmwareMaintenanceTask = nil
            self.stopPersistentMusic(sendRestorePackets: false, reason: "HUD BLE transport disconnected")
            if self.firmwareMaintenanceActive {
                self.firmwareMaintenanceActive = false
                self.maintenance.disconnectADB()
            }
            if self.hudWiFiExposureActive {
                self.hudWiFiExposureActive = false
                self.hudWiFiExposureStatus = "BLE lost — Wi-Fi release armed for reconnect"
                UserDefaults.standard.set(true, forKey: self.hudWiFiRecoveryKey)
            }
            self.obd.transportDisconnected()
            self.routeGuidance.stop(reason: "HUD BLE transport disconnected")
            self.nowPlaying.stop(reason: "HUD BLE transport disconnected")
            self.mainVideo.stop(reason: "HUD BLE transport disconnected")
            self.logger.log(
                "HUD SESSION",
                "BLE transport disconnected; Route Guidance polling stopped and HUD returned to Freeride"
            )

            if self.mapModeActive {
                self.mapModeFrameTask?.cancel()
                self.mapModeFrameTask = nil
                self.mapModeOBDOverlayTask?.cancel()
                self.mapModeOBDOverlayTask = nil
                self.mapModeCastServer.stop()
                self.mapModeActive = false
                self.mapModeStatus = "Map Mode stopped — HUD BLE disconnected; restore armed for reconnect"
                UserDefaults.standard.set(true, forKey: self.hudWiFiRecoveryKey)
            }
        }

        mapModeCastServer.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMapModeCastEvent(event)
            }
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

    /// Dashboard/profile reconstruction on the physical 1.1.27 firmware can
    /// restore the bottom time/weather panel to its boot default after an earlier
    /// OFF packet. Reassert the *current persisted setting* after the profile has
    /// settled. This is debounced because rehydration writes Freeride and
    /// Navigation profiles back-to-back.
    private func scheduleTimeWeatherPostDashboardReassert(reason: String) {
        timeWeatherPostDashboardTask?.cancel()
        timeWeatherPostDashboardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.bluetooth.state == .connected else { return }
            let enabled = self.settings.showTimeWeather
            self.bluetooth.enqueue(
                HudCommands.timeWeather(enabled),
                label: "Post-dashboard time/weather \(enabled) — \(reason)"
            )
            self.logger.log(
                "TIME/WEATHER",
                "Reasserted persisted state=\(enabled ? "ON" : "OFF") after dashboard profile reason=\(reason)"
            )
            self.timeWeatherPostDashboardTask = nil
        }
    }

    /// v90.35 field correction: OFF is now authoritative at cold boot.
    ///
    /// The previous v90.34.16 workaround intentionally sent a transient ON -> OFF
    /// edge when the saved setting was OFF. The 2026-09-11 drive proved that the
    /// transient ON itself can leave the panel visibly enabled. Never transmit ON
    /// from an OFF setting; issue one delayed OFF-only reassert after the final
    /// dashboard/profile reconstruction instead.
    private func scheduleTimeWeatherColdOffSynchronization(reason: String) {
        timeWeatherColdOffSyncTask?.cancel()
        guard !settings.showTimeWeather else { return }

        timeWeatherColdOffSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.timeWeatherColdOffSyncTask = nil }

            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled,
                  self.bluetooth.state == .connected,
                  !self.settings.showTimeWeather else { return }

            self.bluetooth.enqueue(
                HudCommands.timeWeather(false),
                label: "Cold-session time/weather authoritative OFF"
            )
            self.logger.log(
                "TIME/WEATHER",
                "Cold-session delayed OFF-only reassert reason=\(reason); no transient ON packet sent"
            )
        }
    }

    /// Restore the normal dashboard/profile and speed-limit state after a
    /// temporary speed-marker probe, including any D3 stock-Freeride override.
    func restoreHUDAfterSpeedMarkerProbe() {
        guard bluetooth.state == .connected else {
            speedEngine.restoreLiveSpeedLimitStateAfterMarkerProbe()
            return
        }
        obd.applyWidgetSelection()
        restoreDashboardOperatingMode(reason: "speed-marker probe restore")
        applyTimeWeather()
        speedEngine.restoreLiveSpeedLimitStateAfterMarkerProbe()
        logger.log("SPEED MARKER PROBE", "Restored current HUD dashboard + live speed-limit state")
    }

    // MARK: - Original HUDWAY display calibration

    func setDisplayScaleAdjustment(_ value: Int) {
        settings.displayScaleAdjustment = min(100, max(0, value))
        displayScaleApplyTask?.cancel()
        guard bluetooth.state == .connected else {
            logger.log("HUD DISPLAY", "Saved Scale=\(settings.displayScaleAdjustment) while HUD disconnected")
            return
        }
        displayScaleApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard let self, !Task.isCancelled else { return }
            self.applyDisplayScale()
            self.displayScaleApplyTask = nil
        }
    }

    func setDisplayPerspectiveAdjustment(_ value: Int) {
        settings.displayPerspectiveAdjustment = min(100, max(0, value))
        displayPerspectiveApplyTask?.cancel()
        guard bluetooth.state == .connected else {
            logger.log("HUD DISPLAY", "Saved Perspective=\(settings.displayPerspectiveAdjustment) while HUD disconnected")
            return
        }
        displayPerspectiveApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard let self, !Task.isCancelled else { return }
            self.applyDisplayPerspective()
            self.displayPerspectiveApplyTask = nil
        }
    }

    func applyDisplayScale() {
        let wire = settings.displayScaleWireValue
        bluetooth.enqueue(
            HudCommands.layoutSize(wire),
            label: String(format: "HUD Scale %d → layoutSize %.4f", settings.displayScaleAdjustment, Double(wire))
        )
        logger.log("HUD DISPLAY", String(format: "Scale seeker=%d wire=%.4f", settings.displayScaleAdjustment, Double(wire)))
    }

    func applyDisplayPerspective() {
        let wire = settings.displayPerspectiveWireValue
        bluetooth.enqueue(
            HudCommands.keyStone(wire),
            label: String(format: "HUD Perspective %d → keyStone %.4f", settings.displayPerspectiveAdjustment, Double(wire))
        )
        logger.log("HUD DISPLAY", String(format: "Perspective seeker=%d wire=%.4f", settings.displayPerspectiveAdjustment, Double(wire)))
    }

    func applyDisplayCalibration() {
        applyDisplayScale()
        applyDisplayPerspective()
    }

    func resetDisplayCalibrationToStock() {
        displayScaleApplyTask?.cancel()
        displayPerspectiveApplyTask?.cancel()
        settings.displayScaleAdjustment = 0
        settings.displayPerspectiveAdjustment = 0
        if bluetooth.state == .connected {
            applyDisplayCalibration()
        } else {
            logger.log("HUD DISPLAY", "Reset Scale/Perspective to stock 0/0; will reapply on next HUD connection")
        }
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
        scheduleTimeWeatherPostDashboardReassert(reason: "Dashboard preset \(p.name)")
    }



    // MARK: - v90.35.3.6 live relay MJPEG stability + quiet discovery settle
    // U2W v8.14.2 was the persistent-discovery predecessor; v8.14.3 hardens HTTP/MJPEG reconnects.

    func startHUDU2WSTAHomeProbe(ssid: String, password: String) {
        let cleanSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bluetooth.state == .connected else {
            hudU2WSTAStatus = "Connect HUD over BLE first"
            return
        }
        guard !mapModeActive else {
            hudU2WSTAStatus = "Disable legacy Map Mode first"
            return
        }
        guard !cleanSSID.isEmpty, !password.isEmpty else {
            hudU2WSTAStatus = "Enter U2W SSID and password"
            return
        }
        if hudU2WLiveRelayActive {
            let linkUp = hudU2WSTAConnected || isUsableHUDSTAAddress(hudU2WSTAAddress)
            hudU2WSTAStatus = linkUp ? "Relay already active — retrying HUD display…" : "Relay already active — refreshing Wi-Fi join"
            if linkUp {
                primeHUDU2WKivicViewer(reason: "manual Start while active", force: true)
            } else {
                bluetooth.enqueue(HudCommands.kivicMode(6), label: "HUD/U2W active recovery → IOS_KIVICCAST_STA_MODE(6)")
                bluetooth.enqueue(
                    HudCommands.wifiSTAMode(ssid: cleanSSID, password: password, security: 2),
                    label: "HUD/U2W active recovery → Wi-Fi STA credentials for \(cleanSSID)"
                )
                requestHUDU2WSTAStatus()
            }
            return
        }

        // Entering stock mode 6 can emit the same firmware/session hello used during
        // ordinary HUD boot. Normal rehydration writes dashboard/navigation state and
        // can tear down KivicCast STA immediately after it connects. Cancel any pending
        // rehydration before the mode-6 transition; while the relay is active, firmware
        // hello events are intentionally not allowed to start another rehydration cycle.
        hudRehydrateTask?.cancel()
        hudRehydrateTask = nil
        hudReassertTask?.cancel()
        hudReassertTask = nil
        timeWeatherColdOffSyncTask?.cancel()
        timeWeatherColdOffSyncTask = nil

        hudU2WSTAStatusTask?.cancel()
        hudU2WRelayFrameTask?.cancel()
        hudU2WKivicKickTask?.cancel()
        hudU2WFrameRelay.stop(reason: "new relay session")
        hudU2WKivicKickCount = 0
        hudU2WSTAConnected = false
        hudU2WSTAAddress = ""
        hudU2WSTAReason = ""
        hudU2WLiveRelayActive = false
        hudU2WSTAStatus = "Starting U2W v8.14.3 live relay…"
        logger.log("HUD/U2W STA", "live relay start ssid=\(cleanSSID); iPhone remains on U2W AP")

        hudU2WSTAStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = URL(string: "http://192.168.50.2/cgi-bin/u2whud-start.cgi")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 4
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(data: data.prefix(320), encoding: .utf8) ?? ""
                self.logger.log("HUD/U2W STA", "U2W v8.14.3 start HTTP=\(code) response=\(text.replacingOccurrences(of: "\n", with: " | "))")
                guard (200...299).contains(code) else {
                    self.hudU2WSTAStatus = "U2W v8.14.3 start failed (HTTP \(code))"
                    return
                }
            } catch {
                self.hudU2WSTAStatus = "U2W v8.14.3 unreachable"
                self.hudU2WSTAReason = error.localizedDescription
                self.logger.log("HUD/U2W STA", "U2W relay start request failed: \(error.localizedDescription)")
                return
            }

            guard !Task.isCancelled else { return }
            self.hudU2WFrameRelay.start()
            self.hudU2WLiveRelayActive = true
            self.startHUDU2WRelayFrameLoop()

            // v90.35.3.6: do NOT erase the saved STA network before joining.
            // The v90.35.3.4 field log proved that the empty-credentials reset itself
            // reliably drives this HUD into status=6 "Empty network" and can keep it
            // there even after correct credentials are resent. Return briefly to stock
            // HUD mode, then enter STA KivicCast mode and overwrite the credentials
            // non-destructively. This matches the sequence that previously reached
            // status=1 and displayed the map.
            self.hudU2WSTAStatus = "Preparing HUD Wi-Fi…"
            self.bluetooth.enqueue(HudCommands.kivicMode(4), label: "HUD/U2W non-destructive reset → IOS_HUD_MODE(4)")
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            self.hudU2WSTAConnected = false
            self.hudU2WSTAReason = ""
            self.hudU2WSTAStatus = "Joining \(cleanSSID)…"
            self.logger.log("HUD/U2W STA", "entering mode 6 without clearing saved STA credentials")
            self.bluetooth.enqueue(HudCommands.kivicMode(6), label: "HUD/U2W live relay → IOS_KIVICCAST_STA_MODE(6)")
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.bluetooth.enqueue(
                HudCommands.wifiSTAMode(ssid: cleanSSID, password: password, security: 2),
                label: "HUD/U2W live relay → Wi-Fi STA credentials for \(cleanSSID)"
            )

            // Allow association/DHCP to settle, then ask for status. If this firmware
            // returns status=6 together with a valid 192.168.50.x address, the status
            // callback treats that as link-up and immediately kicks the KivicCast viewer.
            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled else { return }
            self.requestHUDU2WSTAStatus()

            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled, !self.hudU2WSTAConnected else { return }

            // One non-destructive credentials refresh only. Never send empty SSID here.
            self.hudU2WSTAStatus = "Still joining — refreshing credentials once…"
            self.bluetooth.enqueue(
                HudCommands.wifiSTAMode(ssid: cleanSSID, password: password, security: 2),
                label: "HUD/U2W live relay → one-shot Wi-Fi credential refresh for \(cleanSSID)"
            )
            try? await Task.sleep(for: .seconds(4.0))
            guard !Task.isCancelled, !self.hudU2WSTAConnected else { return }
            self.requestHUDU2WSTAStatus()
        }
    }

    private func isUsableHUDSTAAddress(_ address: String) -> Bool {
        let parts = address.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ part in
                  guard let value = Int(part) else { return false }
                  return (0...255).contains(value)
              }) else {
            return false
        }
        return address != "0.0.0.0"
    }

    func retryHUDU2WKivicDisplay() {
        guard hudU2WLiveRelayActive else {
            hudU2WSTAStatus = "Start the live relay first"
            return
        }
        let now = Date()
        guard now.timeIntervalSince(hudU2WLastManualDisplayRetryAt) >= 3 else {
            hudU2WSTAStatus = "HUD display retry already in progress…"
            return
        }
        hudU2WLastManualDisplayRetryAt = now
        let linkUp = hudU2WSTAConnected || isUsableHUDSTAAddress(hudU2WSTAAddress)
        guard linkUp else {
            // Allow a forced viewer prime as a diagnostic even if the HUD status
            // packet is ambiguous; field logs show the STA can have DHCP while
            // reporting status=6.
            hudU2WSTAStatus = "Forcing HUD display discovery…"
            bluetooth.enqueue(HudCommands.kivicMode(6), label: "HUD/U2W manual display retry → force IOS_KIVICCAST_STA_MODE(6)")
            bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD/U2W manual display retry → KeepAlive")
            requestHUDU2WSTAStatus()
            return
        }
        hudU2WSTAConnected = true
        primeHUDU2WKivicViewer(reason: "manual display retry", force: true)
    }

    private struct HUDU2WRelayStatus {
        let established: Bool
        let discoverySeen: Bool
        let clientSeen: Bool
        let liveFrameSent: Bool
    }

    private func primeHUDU2WKivicViewer(reason: String, force: Bool = false) {
        guard hudU2WLiveRelayActive, bluetooth.state == .connected else { return }
        if !force, hudU2WKivicKickCount > 0 { return }
        hudU2WKivicKickTask?.cancel()
        hudU2WKivicKickTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, self.hudU2WLiveRelayActive, self.hudU2WSTAConnected else { return }

            self.hudU2WKivicKickCount += 1
            let attempt = self.hudU2WKivicKickCount
            self.bluetooth.enqueue(HudCommands.kivicMode(6), label: "HUD/U2W live relay → post-connect KivicCast viewer prime #\(attempt)")
            self.bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD/U2W live relay → post-connect KeepAlive")
            self.hudU2WSTAStatus = "Wi-Fi connected — requesting HUD stream…"
            self.logger.log("HUD/U2W STA", "post-connect mode-6 viewer prime #\(attempt) reason=\(reason)")

            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled, self.hudU2WLiveRelayActive else { return }
            var relay = await self.u2wHUDRelayStatus()
            if relay.established {
                self.hudU2WSTAStatus = "Connected — HUD stream active"
                self.logger.log("HUD/U2W STA", "U2W confirms active MJPEG client")
                return
            }

            // v90.35.3.6: once the HUD has already emitted KivicCast discovery, do NOT
            // immediately bounce mode 6 again. Field logs show the discovery reply can
            // arrive just before the HUD opens HTTP/15330; an eager second mode-6 packet
            // tears down that in-flight viewer session. Give it a quiet settle window.
            if relay.discoverySeen || relay.clientSeen {
                self.hudU2WSTAStatus = relay.clientSeen
                    ? "HUD contacted video server — waiting for stream…"
                    : "HUD discovery received — waiting for video connection…"
                self.logger.log(
                    "HUD/U2W STA",
                    "viewer discovery already active; suppressing automatic mode-6 retry discovery=\(relay.discoverySeen) clientSeen=\(relay.clientSeen)"
                )

                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, self.hudU2WLiveRelayActive else { return }
                relay = await self.u2wHUDRelayStatus()
                if relay.established {
                    self.hudU2WSTAStatus = "Connected — HUD stream active"
                } else if relay.clientSeen {
                    self.hudU2WSTAStatus = relay.liveFrameSent
                        ? "HUD video client connected, but stream dropped — use Retry display once"
                        : "HUD contacted video server — waiting; use Retry display once if blank"
                } else {
                    self.hudU2WSTAStatus = "Wi-Fi connected — discovery succeeded; use Retry display once if still blank"
                }
                return
            }

            // Only retry mode 6 automatically when U2W has seen no discovery at all.
            if attempt < 2, self.hudU2WSTAConnected {
                self.hudU2WSTAStatus = "Wi-Fi connected — retrying HUD discovery…"
                self.hudU2WKivicKickCount += 1
                let retry = self.hudU2WKivicKickCount
                self.bluetooth.enqueue(HudCommands.kivicMode(6), label: "HUD/U2W live relay → KivicCast viewer retry #\(retry) (no discovery)")
                self.bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD/U2W live relay → retry KeepAlive")
                self.logger.log("HUD/U2W STA", "no discovery observed; viewer retry #\(retry)")
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, self.hudU2WLiveRelayActive else { return }
                relay = await self.u2wHUDRelayStatus()
                self.hudU2WSTAStatus = relay.established
                    ? "Connected — HUD stream active"
                    : (relay.discoverySeen
                        ? "Wi-Fi connected — discovery succeeded; waiting for HUD video…"
                        : "Wi-Fi connected — no HUD discovery yet; use Retry display")
            } else {
                self.hudU2WSTAStatus = "Wi-Fi connected — no HUD discovery yet; use Retry display"
            }
        }
    }

    private func u2wHUDRelayStatus() async -> HUDU2WRelayStatus {
        guard let url = URL(string: "http://192.168.50.2/cgi-bin/u2whud-status.cgi") else {
            return HUDU2WRelayStatus(established: false, discoverySeen: false, clientSeen: false, liveFrameSent: false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                return HUDU2WRelayStatus(established: false, discoverySeen: false, clientSeen: false, liveFrameSent: false)
            }
            let status = HUDU2WRelayStatus(
                established: text.contains("hud_mjpeg_established=YES"),
                discoverySeen: text.contains("discovery-packet-received"),
                clientSeen: text.contains("hud-mjpeg-client-connected") || text.contains("hud_client_seen=YES"),
                liveFrameSent: text.contains("live-frame-sent") || text.contains("live_frame_sent=YES")
            )
            self.logger.log(
                "HUD/U2W STA",
                "relay status mjpegEstablished=\(status.established) discoverySeen=\(status.discoverySeen) clientSeen=\(status.clientSeen) liveFrameSent=\(status.liveFrameSent)"
            )
            return status
        } catch {
            self.logger.log("HUD/U2W STA", "relay status query failed: \(error.localizedDescription)")
            return HUDU2WRelayStatus(established: false, discoverySeen: false, clientSeen: false, liveFrameSent: false)
        }
    }

    private func startHUDU2WRelayFrameLoop() {
        hudU2WRelayFrameTask?.cancel()
        hudU2WRelayFrameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.hudU2WLiveRelayActive {
                let snapshot = self.makeMapModeSnapshot(
                    useFrozenRouteWhenUnavailable: false,
                    allowDesignFallback: true
                )
                if let frame = HudMapModeFrameRenderer.jpeg(
                    snapshot: snapshot,
                    settings: self.mapModeSettings,
                    sourceMapImage: self.mainVideo.latestFrame,
                    suppressCustomSpeedForNativeOBDProbe: false
                ) {
                    self.hudU2WFrameRelay.sendFrame(frame)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func requestHUDU2WSTAStatus() {
        guard bluetooth.state == .connected else {
            hudU2WSTAStatus = "HUD BLE disconnected"
            return
        }
        bluetooth.enqueue(HudCommands.wifiSTAStatusRequest(), label: "HUD/U2W live relay → request STA status")
        logger.log("HUD/U2W STA", "Requested stock WifiSTAStatusEventPacket")
    }

    func stopHUDU2WSTAHomeProbe() {
        hudU2WSTAStatusTask?.cancel()
        hudU2WSTAStatusTask = nil
        hudU2WRelayFrameTask?.cancel()
        hudU2WRelayFrameTask = nil
        hudU2WKivicKickTask?.cancel()
        hudU2WKivicKickTask = nil
        hudU2WKivicKickCount = 0
        hudU2WSTAResetInProgress = false
        hudU2WIgnoreEmptyStatusUntil = .distantPast
        hudU2WFrameRelay.stop(reason: "relay stopped")
        hudU2WLiveRelayActive = false
        hudU2WSTAConnected = false
        hudU2WSTAAddress = ""
        hudU2WSTAReason = ""
        hudU2WSTAStatus = "Stopping…"

        if bluetooth.state == .connected {
            // Do not erase the saved STA credentials on every stop. Field logs showed
            // the asynchronous "Empty network" response from that clear command could
            // bleed into the next start and poison rapid retry attempts. Mode 4 is
            // sufficient to leave KivicCast; the next start can reuse/overwrite the
            // credentials normally.
            bluetooth.enqueue(HudCommands.kivicMode(4), label: "HUD/U2W live relay → restore IOS_HUD_MODE(4) (preserve STA credentials)")
            restoreDashboardOperatingMode(reason: "HUD/U2W live relay stopped")
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let url = URL(string: "http://192.168.50.2/cgi-bin/u2whud-stop.cgi") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 3
                _ = try? await URLSession.shared.data(for: request)
            }
            self.hudU2WSTAStatus = "Stopped — normal HUD mode restored"
            self.logger.log("HUD/U2W STA", "live relay stopped; mode 4 restore requested")
        }
    }

    // MARK: - Navigation presentation / lane guidance

    var laneGuidanceThresholdMeters: Int {
        Int((settings.laneGuidanceDistanceMiles * 1609.344).rounded())
    }

    func receiveLiveLaneGuidance(_ state: RouteGuidanceAdapterClient.LiveLaneGuidanceState?) {
        guard let state else {
            guard liveLaneSessionActive else { return }
            logger.log("CARPLAY LANE", "Live Route Guidance ended; clearing live lane state")
            liveLaneSessionActive = false
            liveLaneCacheByManeuver.removeAll()
            liveLaneCurrentManeuverIndex = nil
            liveLaneSource = nil
            liveLaneLastRouteState = nil
            activeLiveLaneGuidanceIndex = nil
            activeLiveLaneEventIndex = nil
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "live Route Guidance inactive")
            }
            return
        }

        liveLaneSessionActive = true

        if liveLaneSource != state.source {
            if let previous = liveLaneSource {
                logger.log("CARPLAY LANE", "Source changed \(previous) → \(state.source); dropping old live lane state")
            }
            liveLaneCacheByManeuver.removeAll()
            liveLaneCurrentManeuverIndex = nil
            activeLiveLaneGuidanceIndex = nil
            activeLiveLaneEventIndex = nil
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "CarPlay source changed")
            }
            liveLaneSource = state.source
        }

        let enteredReroute = state.routeState == 5 && liveLaneLastRouteState != 5
        if enteredReroute {
            liveLaneCacheByManeuver.removeAll()
            liveLaneCurrentManeuverIndex = nil
            activeLiveLaneGuidanceIndex = nil
            activeLiveLaneEventIndex = nil
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "CarPlay reroute started")
            }
            logger.log("CARPLAY LANE", "Reroute state 5 entered; old lane state cleared")
        }
        liveLaneLastRouteState = state.routeState

        // Google Maps can transiently move the exported maneuver cursor backward
        // while its route table stabilizes. v90.34.6 treated every backward move
        // as a new route and repeatedly deleted valid lane data. Cursor movement
        // is now diagnostic only; explicit source/reroute/session evidence owns
        // lane-session resets.
        if let currentIndex = state.currentManeuverIndex,
           liveLaneCurrentManeuverIndex != currentIndex {
            let previous = liveLaneCurrentManeuverIndex.map(String.init) ?? "nil"
            liveLaneCurrentManeuverIndex = currentIndex
            logger.log(
                "CARPLAY LANE CURSOR",
                "current maneuver \(previous) → \(currentIndex) routeSeq=\(state.routeSequence) distance=\(state.distanceToManeuverMeters)m (no cache reset on cursor wobble)"
            )
        }

        if state.schemaVersion >= 2 {
            receiveResolvedV88LaneGuidance(state)
        } else {
            receiveLegacyV87LaneGuidance(state)
        }
    }

    /// U2W v8.8 resolves the protocol correctly on the adapter:
    /// 0x5204 TLV1 is a composedGuidanceEventIndex and 0x5201 InfoType 16
    /// selects the active event from that cache. The iPhone therefore consumes
    /// the already-resolved current lane event instead of guessing a mapping to
    /// the independently moving route-maneuver cursor.
    private func receiveResolvedV88LaneGuidance(_ state: RouteGuidanceAdapterClient.LiveLaneGuidanceState) {
        // The physical Google Maps capture establishes two distinct concepts:
        //   * 0x5204 events may be pre-cached well before they are needed.
        //   * 0x5201 InfoType 16 selects an event, while InfoType 18 says whether
        //     CarPlay is actively presenting that event right now.
        // A selector value of 0 is both a valid event id and the value observed
        // when Google Maps hides lane guidance. Therefore laneGuidanceShowing is
        // the activation edge; Persistent/Near-turn policy may keep an already
        // activated event after that flag falls, but a hidden selector must never
        // replace the latched event with cached event 0.
        let currentIndex = state.currentManeuverIndex

        if state.routeState == 0 {
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "v8.8 route ended")
            }
            return
        }

        if state.laneGuidanceShowing {
            guard let currentIndex else {
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "showing=1 but current route maneuver is unresolved routeSeq=\(state.routeSequence); waiting before latching lanes"
                )
                return
            }
            guard let selectedIndex = state.laneGuidanceIndex else {
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "showing=1 but v8.8 selector missing routeSeq=\(state.routeSequence) current=\(String(currentIndex))"
                )
                if activeLaneIsLive,
                   let activeManeuver = activeLiveLaneManeuverIndex,
                   activeManeuver != currentIndex {
                    clearLaneGuidancePolicy(reason: "new maneuver has no resolved v8.8 selector")
                }
                return
            }

            guard !state.lanes.isEmpty,
                  let laneSequence = state.laneSequence else {
                // The selector can precede its matching pre-cached 0x5204 packet.
                // Never substitute another cached event. If the route cursor has
                // already advanced, remove the old maneuver's lanes while waiting.
                if activeLaneIsLive,
                   let activeManeuver = activeLiveLaneManeuverIndex,
                   activeManeuver != currentIndex {
                    clearLaneGuidancePolicy(reason: "v8.8 selected event not resolved for new maneuver")
                }
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "showing=1 selector=\(selectedIndex) unresolved routeSeq=\(state.routeSequence) current=\(String(currentIndex))"
                )
                return
            }

            let eventIndex = state.laneGuidanceEventIndex ?? selectedIndex
            if eventIndex != selectedIndex {
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "selector/event mismatch selector=\(selectedIndex) event=\(eventIndex); accepting exporter-resolved event"
                )
            }

            let context = "Live U2W v8.8 \(state.source) guidance=\(selectedIndex) event=\(eventIndex) laneSeq=\(laneSequence)"
            let changed = !activeLaneIsLive ||
                activeLiveLaneGuidanceIndex != selectedIndex ||
                activeLiveLaneEventIndex != eventIndex ||
                activeLiveLaneManeuverIndex != currentIndex ||
                activeLaneGuidance != state.lanes

            activeLiveLaneGuidanceIndex = selectedIndex
            activeLiveLaneEventIndex = eventIndex
            activeLiveLaneManeuverIndex = currentIndex

            if changed {
                setLaneGuidanceForCurrentManeuver(
                    state.lanes,
                    distanceMeters: state.distanceToManeuverMeters,
                    context: context,
                    isLive: true
                )
                // setLaneGuidanceForCurrentManeuver intentionally preserves the
                // live maneuver binding populated above.
                activeLiveLaneManeuverIndex = currentIndex
                logger.log(
                    "CARPLAY LANE ACTIVATE",
                    "v8.8 selector=\(selectedIndex) event=\(eventIndex) maneuver=\(String(currentIndex)) laneSeq=\(laneSequence) distance=\(state.distanceToManeuverMeters)m policy=\(settings.laneGuidanceMode.title) showingFlag=1 values=[\(state.lanes.map { String($0.wireValue) }.joined(separator: ","))]"
                )
            } else {
                updateActiveLaneDistanceMeters(state.distanceToManeuverMeters, context: context)
            }
            return
        }

        // CarPlay hid its stock lane layer. For custom Persistent/Near-turn
        // behavior, retain the last event only while we are still on the same
        // route maneuver. This is what makes Persistent actually persist without
        // allowing Google Maps' hidden selector=0 to overwrite the active event.
        if activeLaneIsLive {
            if let activeManeuver = activeLiveLaneManeuverIndex,
               let currentIndex,
               activeManeuver != currentIndex {
                logger.log(
                    "CARPLAY LANE LIFETIME",
                    "maneuver advanced \(activeManeuver) → \(currentIndex) while showing=0; clearing latched event guidance=\(activeLiveLaneGuidanceIndex.map(String.init) ?? "nil")"
                )
                clearLaneGuidancePolicy(reason: "live lane maneuver completed")
            } else {
                updateActiveLaneDistanceMeters(
                    state.distanceToManeuverMeters,
                    context: activeLaneContext
                )
                logger.log(
                    "CARPLAY LANE LATCH",
                    "showing=0 selector=\(state.laneGuidanceIndex.map(String.init) ?? "nil") ignored; keeping event=\(activeLiveLaneEventIndex.map(String.init) ?? "nil") maneuver=\(activeLiveLaneManeuverIndex.map(String.init) ?? "nil") policy=\(settings.laneGuidanceMode.title)"
                )
            }
        }
    }

    /// Backward-compatible fallback for U2W v8.7. That exporter incorrectly
    /// labeled the 0x5204 composed event id as maneuverIndex and retained only
    /// the last event of a burst, so complete live lane behavior is impossible
    /// with v8.7. Keep the old best-effort mapping without allowing transient
    /// backward cursor movement to wipe the cache.
    private func receiveLegacyV87LaneGuidance(_ state: RouteGuidanceAdapterClient.LiveLaneGuidanceState) {
        if !loggedLegacyV87LaneSchema {
            loggedLegacyV87LaneSchema = true
            logger.log("CARPLAY LANE", "U2W v8.7 lane schema detected; best-effort only — install v8.8 for active-event resolution")
        }

        if !state.lanes.isEmpty,
           let laneSequence = state.laneSequence,
           let laneIndex = state.laneManeuverIndex ?? state.currentManeuverIndex {
            let entry = LiveLaneCacheEntry(
                laneSequence: laneSequence,
                lanes: state.lanes,
                rawSummary: state.rawSummary
            )
            if liveLaneCacheByManeuver[laneIndex] != entry {
                liveLaneCacheByManeuver[laneIndex] = entry
                logger.log(
                    "CARPLAY LANE CACHE",
                    "legacy-v8.7 routeSeq=\(state.routeSequence) laneSeq=\(laneSequence) legacyIndex=\(laneIndex) values=[\(state.lanes.map { String($0.wireValue) }.joined(separator: ","))]"
                )
            }
        }

        guard let currentIndex = state.currentManeuverIndex,
              let cached = liveLaneCacheByManeuver[currentIndex] else { return }

        let context = "Legacy U2W v8.7 \(state.source) index=\(currentIndex) laneSeq=\(cached.laneSequence)"
        if !activeLaneIsLive || activeLiveLaneManeuverIndex != currentIndex || activeLaneGuidance != cached.lanes {
            activeLiveLaneManeuverIndex = currentIndex
            setLaneGuidanceForCurrentManeuver(
                cached.lanes,
                distanceMeters: state.distanceToManeuverMeters,
                context: context,
                isLive: true
            )
        } else {
            updateActiveLaneDistanceMeters(state.distanceToManeuverMeters, context: context)
        }
    }

    private func reassertLiveLaneAfterManeuverDelivery(maneuverIndex: Int?) {
        guard bluetooth.state == .connected,
              activeLaneIsLive,
              shouldDisplayActiveLanes(),
              let activeManeuver = activeLiveLaneManeuverIndex,
              let maneuverIndex,
              activeManeuver == maneuverIndex else { return }
        // The stock firmware can clear the lane layer when the maneuver packet
        // redraws. Re-send lanes in the same BLE queue immediately after every
        // delivery of the *same* maneuver that owns the latched lane event. A
        // newly advanced maneuver must never receive the previous turn's lanes.
        sendActiveLaneGuidance(label: "Lane policy → post-maneuver reassert")
        logger.log(
            "CARPLAY LANE REASSERT",
            "after maneuver delivery index=\(maneuverIndex) guidance=\(activeLiveLaneGuidanceIndex.map(String.init) ?? "nil")"
        )
    }

    private func updateActiveLaneDistanceMeters(_ distanceMeters: Int, context: String) {
        let wasVisible = shouldDisplayActiveLanes()
        activeLaneDistanceMeters = max(0, distanceMeters)
        activeLaneContext = context
        let isVisible = shouldDisplayActiveLanes()
        if wasVisible != isVisible {
            logger.log(
                "HUD LANE POLICY",
                "distance gate crossed distance=\(activeLaneDistanceMeters)m threshold=\(laneGuidanceThresholdMeters)m visible=\(isVisible)"
            )
            reevaluateActiveLaneGuidance(reason: "live distance threshold crossed")
        }
    }

    func applyNavigationPresentationSettings() {
        navigation.showCurrentStreet = settings.navigationShowCurrentStreet
        navigation.showCurrentTurnText = settings.navigationShowCurrentTurnText
        logger.log(
            "NAV PRESENTATION",
            "currentStreet=\(settings.navigationShowCurrentStreet ? "ON" : "OFF") " +
            "turnText=\(settings.navigationShowCurrentTurnText ? "ON" : "OFF") lanes=\(settings.laneGuidanceMode.title) " +
            "threshold=\(String(format: "%.1f", settings.laneGuidanceDistanceMiles))mi placement=\(settings.lanePlacementMode.title)"
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
            restoreNormalNavigationAfterLaneProbeIfNeeded(reason: "lane hidden: \(reason)")
            logger.log(
                "HUD LANE POLICY",
                "hidden reason=\(reason) mode=\(settings.laneGuidanceMode.title) distance=\(activeLaneDistanceMeters)m threshold=\(laneGuidanceThresholdMeters)m placement=\(settings.lanePlacementMode.title)"
            )
            return
        }

        if settings.lanePlacementMode == .centerNative {
            restoreNormalNavigationAfterLaneProbeIfNeeded(reason: "center-native selected")
        } else {
            activateRightLaneWidgetProbeIfNeeded(reason: reason)
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

    private func activateRightLaneWidgetProbeIfNeeded(reason: String) {
        guard navigation.navigationActive,
              let rightWidget = settings.lanePlacementMode.rightWidgetName else { return }

        // v90.34.10.1 latched only a Boolean. If the user changed from the
        // Navigation probe to NaviMini while lanes were already visible, the
        // guard returned early and the HUD never received the new right-widget
        // dashboard packet. Track the active candidate so a placement change
        // reconfigures the right side immediately during parked replay.
        let reconfiguring = laneRightSideProbeActive && laneRightSideProbeWidget != rightWidget
        if laneRightSideProbeActive && !reconfiguring { return }

        laneRightSideProbeActive = true
        laneRightSideProbeWidget = rightWidget
        // Static firmware inspection shows setLaneInstructions() fans the same
        // lane list to center/left/right widgets. Keep the proven center
        // Navigation widget in place for a safe road test, while temporarily
        // replacing the normal right-side ETA with the selected candidate. If
        // that candidate implements lanes, we should see a second/right-side
        // response. The center gray lane box may still appear during this probe
        // because the stock command cannot address one widget independently.
        bluetooth.enqueue(
            HudCommands.dashboard(
                left: obd.navigationLeft.rawValue,
                center: "Navigation",
                right: rightWidget,
                navigationLayout: true
            ),
            label: "Lane right-side probe → \(rightWidget)"
        )
        logger.log(
            "HUD LANE PROBE",
            "\(reconfiguring ? "reconfigure" : "activate") right=\(rightWidget) replaces ETA center=Navigation reason=\(reason); stock-only/no filesystem write"
        )
        scheduleTimeWeatherPostDashboardReassert(reason: "Lane right-side probe dashboard")

        // setWidgets() creates a fresh widget and hydrates cached values, but
        // explicitly re-send the current maneuver so any hidden side navigation
        // implementation receives the same native maneuver state before lanes.
        navigation.sendCurrent(owner: navigation.feedOwner)
    }

    private func restoreNormalNavigationAfterLaneProbeIfNeeded(reason: String) {
        guard laneRightSideProbeActive else { return }
        laneRightSideProbeActive = false
        laneRightSideProbeWidget = nil
        guard bluetooth.state == .connected else { return }
        obd.applyNavigationWidgets()
        if navigation.navigationActive {
            navigation.sendCurrent(owner: navigation.feedOwner)
        }
        logger.log(
            "HUD LANE PROBE",
            "restore normal Navigation dashboard right=\(obd.navigationRight.rawValue) reason=\(reason)"
        )
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
        context: String,
        isLive: Bool = false
    ) {
        activeLaneGuidance = lanes
        activeLaneDistanceMeters = max(0, distanceMeters)
        activeLaneContext = context
        activeLaneIsLive = isLive
        if !isLive {
            activeLiveLaneManeuverIndex = nil
        }
        reevaluateActiveLaneGuidance(reason: "new lane data")
    }

    func clearLaneGuidancePolicy(reason: String = "manual clear") {
        laneGuidanceRefreshTask?.cancel()
        laneGuidanceRefreshTask = nil
        activeLaneGuidance = []
        activeLaneDistanceMeters = 0
        activeLaneContext = ""
        activeLaneIsLive = false
        activeLiveLaneManeuverIndex = nil
        activeLiveLaneGuidanceIndex = nil
        activeLiveLaneEventIndex = nil
        guard bluetooth.state == .connected else {
            laneRightSideProbeActive = false
            laneRightSideProbeWidget = nil
            return
        }
        bluetooth.enqueue(HudCommands.clearLaneGuidance(), label: "Lane guidance clear")
        restoreNormalNavigationAfterLaneProbeIfNeeded(reason: "lane policy cleared: \(reason)")
        logger.log("HUD LANE POLICY", "clear reason=\(reason)")
    }

    // MARK: - v90.35 custom Map Mode cast

    var mapModePreviewSnapshot: HudMapModeSnapshot {
        makeMapModeSnapshot(useFrozenRouteWhenUnavailable: mapModeActive, allowDesignFallback: true)
    }

    var mapModePreviewSourceImage: UIImage? {
        mapModeActive ? (mapModeFrozenSourceImage ?? mainVideo.latestFrame) : mainVideo.latestFrame
    }

    func enableMapMode() {
        guard !hudU2WLiveRelayActive else {
            mapModeStatus = "Stop the live U2W relay before using legacy mode-5 Map Mode"
            logger.log("MAP MODE", "Legacy mode-5 start blocked while live U2W relay is active")
            return
        }
        guard bluetooth.state == .connected else {
            mapModeStatus = "Connect the HUD over BLE first"
            return
        }
        guard !firmwareMaintenanceActive else {
            mapModeStatus = "Exit HUD Firmware Maintenance before starting Map Mode"
            return
        }
        guard !mapModeActive else { return }

        mapModeFrozenSnapshot = makeMapModeSnapshot(
            useFrozenRouteWhenUnavailable: false,
            allowDesignFallback: true
        )
        // Freeze the latest decoded U2W MainVideo frame before Wi-Fi moves from
        // Carlinkit to the HUD AP. The iPhone cannot remain associated with both
        // networks, so the physical mode-5 cast uses this last real map frame
        // unless a future shared-network path is physically validated.
        mapModeFrozenSourceImage = mainVideo.latestFrame
        mainVideo.stop(reason: "Map Mode HUD-Wi-Fi handoff — freeze last U2W frame")
        // Freeze the last U2W semantic route before Wi-Fi moves from Carlinkit
        // to the HUD AP. This prevents adapter timeout/release packets from
        // fighting the casting experiment while the two networks are mutually
        // exclusive on the iPhone. Normal polling resumes on Map Mode exit.
        routeGuidance.stop(reason: "Map Mode frozen-route Wi-Fi handoff")
        nowPlaying.stop(reason: "Map Mode HUD Wi-Fi handoff")
        mapModeActive = true
        mapModeStatus = "Starting Map Mode cast server…"
        mapModeLastNetworkEvent = "Starting"
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)

        do {
            try mapModeCastServer.start()
        } catch {
            mapModeActive = false
            mapModeStatus = "Could not start Map Mode cast server: \(error.localizedDescription)"
            routeGuidance.start(reason: "Map Mode cast-server start failed")
            nowPlaying.start(reason: "Map Mode cast-server start failed")
            mainVideo.start(reason: "Map Mode cast-server start failed")
            UserDefaults.standard.set(false, forKey: hudWiFiRecoveryKey)
            logger.log("MAP MODE", "Cast server start failed: \(error.localizedDescription)")
            return
        }

        startMapModeFrameLoop()

        // Exact stock iOS casting AP bootstrap already validated on HUD FW 1.1.27.
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "Map Mode → stock 5GHz HUD AP"
        )
        bluetooth.enqueue(HudCommands.kivicMode(5), label: "Map Mode → IOS_KIVICCAST_MODE(5)")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "Map Mode → KeepAlive")
        logger.log(
            "MAP MODE",
            "Enabled custom cast; frozen route=\(mapModeFrozenSnapshot?.turningStreet ?? "—") " +
            "OBDOverlayProbe=\(mapModeSettings.nativeOBDSpeedOverlayExperiment)"
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.mapModeActive else { return }
            if !self.mapModeStatus.contains("streaming") {
                self.mapModeStatus = "HUD AP ready — join HUDWAY Drive Wi-Fi on iPhone; cast starts after KivicCast discovery"
            }
        }
    }

    func disableMapMode(reason: String = "manual") {
        mapModeFrameTask?.cancel()
        mapModeFrameTask = nil
        mapModeOBDOverlayTask?.cancel()
        mapModeOBDOverlayTask = nil
        mapModeCastServer.stop()
        mapModeActive = false
        mapModeFrozenSnapshot = nil
        mapModeFrozenSourceImage = nil

        guard bluetooth.state == .connected else {
            mapModeStatus = "Map Mode stopped locally — HUD restore armed for next BLE connection"
            UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)
            return
        }

        // Clear the experimental OBD custom slot, release KivicCast mode and
        // reconstruct exactly the normal Freeride/Navigation state.
        bluetooth.enqueue(
            HudCommands.obdCustomItem(position: 0, itemIndex: Int32(HudOBDItem.none.rawValue)),
            label: "Map Mode → clear native OBD speed overlay probe"
        )
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "Map Mode → stock HUD AP release"
        )
        bluetooth.enqueue(HudCommands.kivicMode(4), label: "Map Mode → restore IOS_HUD_MODE(4)")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "Map Mode → restore full screen")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "Map Mode → restore KeepAlive")
        obd.applyWidgetSelection()
        restoreDashboardOperatingMode(reason: "Map Mode disabled / \(reason)")
        applyTimeWeather()
        reevaluateActiveLaneGuidance(reason: "Map Mode disabled")
        speedEngine.reassertOriginalSpeedMarker(reason: "Map Mode disabled")
        routeGuidance.start(reason: "Map Mode disabled — resume U2W polling")
        nowPlaying.start(reason: "Map Mode disabled — resume U2W polling")
        mainVideo.start(reason: "Map Mode disabled — resume U2W main video")
        UserDefaults.standard.set(false, forKey: hudWiFiRecoveryKey)
        mapModeStatus = "Map Mode off — normal Freeride/Navigation restored"
        logger.log("MAP MODE", "Disabled reason=\(reason); normal HUD state restored")
    }

    private func startMapModeFrameLoop() {
        mapModeFrameTask?.cancel()
        mapModeFrameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.mapModeActive {
                let snapshot = self.makeMapModeSnapshot(
                    useFrozenRouteWhenUnavailable: true,
                    allowDesignFallback: true
                )
                let suppressSpeed = self.mapModeSettings.nativeOBDSpeedOverlayExperiment && self.obd.connected
                if let frame = HudMapModeFrameRenderer.jpeg(
                    snapshot: snapshot,
                    settings: self.mapModeSettings,
                    sourceMapImage: self.mapModeFrozenSourceImage ?? self.mainVideo.latestFrame,
                    suppressCustomSpeedForNativeOBDProbe: suppressSpeed
                ) {
                    self.mapModeCastServer.updateFrame(frame)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func handleMapModeCastEvent(_ event: String) {
        mapModeLastNetworkEvent = event
        logger.log("MAP CAST", event)
        guard mapModeActive else { return }
        if event.contains("HUD MJPEG client streaming") {
            mapModeStatus = "Map Mode streaming to HUD"
            startNativeOBDSpeedOverlayProbeIfNeeded()
        } else if event.contains("HUD discovered Map Mode stream") {
            mapModeStatus = "HUD discovered iPhone Map Mode stream — opening MJPEG"
        }
    }

    private func startNativeOBDSpeedOverlayProbeIfNeeded() {
        mapModeOBDOverlayTask?.cancel()
        guard mapModeSettings.nativeOBDSpeedOverlayExperiment else {
            logger.log("MAP OBD PROBE", "Disabled by user")
            return
        }
        guard obd.connected else {
            logger.log("MAP OBD PROBE", "Skipped: HUD-side OBD is not connected")
            mapModeStatus = "Map Mode streaming — native OBD speed probe waiting for OBD"
            return
        }

        mapModeOBDOverlayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // KivicCast normally hides the stock widget layer. Reassert the
            // exact recovered custom OBD item after streaming begins and try the
            // non-fullscreen HUD visibility state. No APK/filesystem write occurs.
            self.bluetooth.enqueue(HudCommands.fullScreen(false), label: "Map OBD probe → stock HUD layer visible")
            for attempt in 1...3 {
                guard !Task.isCancelled, self.mapModeActive, self.bluetooth.state == .connected else { return }
                self.bluetooth.enqueue(
                    HudCommands.obdCustomItem(
                        position: 0,
                        itemIndex: Int32(HudOBDItem.drivingVelocity.rawValue)
                    ),
                    label: "Map OBD probe → Driving velocity position 0 attempt \(attempt)"
                )
                self.bluetooth.enqueue(HudCommands.keepAlive(), label: "Map OBD probe → KeepAlive \(attempt)")
                self.logger.log(
                    "MAP OBD PROBE",
                    "Sent stock OBD_DRIVING_VELOCITY itemIndex=10 position=0 attempt=\(attempt); custom cast speed intentionally blank"
                )
                try? await Task.sleep(for: .milliseconds(1200))
            }
            self.mapModeStatus = "Map Mode streaming — native OBD speed overlay probe sent"
        }
    }

    private func makeMapModeSnapshot(
        useFrozenRouteWhenUnavailable: Bool,
        allowDesignFallback: Bool
    ) -> HudMapModeSnapshot {
        let speed = speedEngine.currentSpeedMph
        let limit = speedEngine.currentSpeedLimitMph
        let liveRoute = routeGuidance.selectedSource != "—"

        var distance = routeGuidance.distanceToManeuverText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if distance.isEmpty || distance == "—" {
            distance = navigation.current.displayDistanceText
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if distance.isEmpty, navigation.current.distanceMeters > 0 {
            let feet = Int((Double(navigation.current.distanceMeters) * 3.28084).rounded())
            distance = feet >= 5280
                ? String(format: "%.1f mi", Double(feet) / 5280.0)
                : "\(feet) ft"
        }

        let current = HudMapModeSnapshot(
            speedMph: speed,
            speedLimitMph: limit,
            currentRoad: routeGuidance.currentRoad,
            turningStreet: navigation.current.streetName,
            maneuver: navigation.current.maneuver,
            distanceText: distance,
            destination: routeGuidance.destination,
            etaText: routeGuidance.etaText,
            timeLeftText: Self.mapModeTimeLeftText(routeGuidance.timeRemainingSeconds),
            laneValues: activeLaneGuidance.map { Int($0.wireValue) },
            routeRoads: routeGuidance.routeRoads,
            hasLiveRoute: liveRoute
        )

        if liveRoute { return current }

        if useFrozenRouteWhenUnavailable, var frozen = mapModeFrozenSnapshot {
            frozen.speedMph = speed
            frozen.speedLimitMph = limit
            if !activeLaneGuidance.isEmpty {
                frozen.laneValues = activeLaneGuidance.map { Int($0.wireValue) }
            }
            return frozen
        }

        guard allowDesignFallback else { return current }
        var fallback = HudMapModeSnapshot.previewFallback
        fallback.speedMph = speed > 0 ? speed : fallback.speedMph
        fallback.speedLimitMph = limit > 0 ? limit : fallback.speedLimitMph
        return fallback
    }

    private static func mapModeTimeLeftText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 60 { return "<1 min" }
        let minutes = Int(ceil(Double(seconds) / 60.0))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours) hr" : "\(hours) hr \(remaining) min"
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
        hudWiFiExposureStatus = "Starting stock 5-GHz HUDWAY AP…"
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)

        // Physical stock-app log, HUD FW 1.1.27:
        //   HudHotspotBaseband(is5G:true, forceEnable:false)
        //   KivicMode(5)
        // Then HudLauncher itself starts WifiApEnabler ~2.6 s later, hostapd,
        // tethering/dnsmasq, and wlan0=192.168.43.1. Do NOT return to mode 4
        // during this bootstrap; v90.34.5.2 did so at 1.8 s and aborted it.
        logger.log(
            "HUD WIFI",
            "Stock AP bootstrap: 5GHz force=false → IOS_KIVICCAST_MODE(5); hold mode 5 for full SoftAP/DHCP startup"
        )
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "HUD Wi-Fi → stock 5GHz baseband (force OFF)"
        )
        bluetooth.enqueue(HudCommands.kivicMode(5), label: "HUD Wi-Fi → stock iOS KivicCast mode 5")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → bootstrap KeepAlive")

        hudWiFiExposureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(5000))
            guard !Task.isCancelled, self.hudWiFiExposureActive,
                  self.bluetooth.state == .connected else { return }
            // Stay in mode 5 for the whole maintenance session. Physical testing
            // proved forceEnable=true tears the SoftAP down, so that experiment is retired.
            self.hudWiFiExposureStatus = "Stock AP startup complete — join HUDWAY Wi-Fi; mode 5 held"
            self.bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → post-bootstrap KeepAlive")
            self.hudWiFiExposureTask = nil
        }
    }

    /// Re-run the exact stock AP bootstrap and remain in IOS_KIVICCAST_MODE(5).
    func holdHUDWiFiCastingModeForDiagnostics() {
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "Connect the HUD over BLE first"
            return
        }
        hudWiFiExposureTask?.cancel()
        hudWiFiExposureActive = true
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)
        logger.log("HUD WIFI", "Diagnostic: restart exact stock 5GHz force=false + IOS_KIVICCAST_MODE(5)")
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "HUD Wi-Fi diagnostic → stock 5GHz baseband"
        )
        bluetooth.enqueue(HudCommands.kivicMode(5), label: "HUD Wi-Fi diagnostic → hold iOS KivicCast mode 5")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi diagnostic → KeepAlive")
        hudWiFiExposureStatus = "Stock cast mode 5 held — allow ~5 s, then reconnect laptop"
        hudWiFiExposureTask = nil
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
        // Match the stock OFF transition captured from the original HUDWAY app.
        logger.log("HUD WIFI", "Disable HUD AP reason=\(reason): stock 5GHz force=false + IOS_HUD_MODE(4)")
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "HUD Wi-Fi → stock AP release"
        )
        bluetooth.enqueue(HudCommands.kivicMode(4), label: "HUD Wi-Fi → restore iOS HUD mode 4")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "HUD Wi-Fi → full screen ON")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → KeepAlive")
        UserDefaults.standard.set(false, forKey: hudWiFiRecoveryKey)
        hudWiFiExposureStatus = "HUD Wi-Fi released"
    }

    // MARK: - HUD firmware maintenance / boot animation override

    func startFirmwareMaintenance() {
        guard bluetooth.state == .connected else {
            maintenance.status = "Connect the HUD over BLE first"
            return
        }
        firmwareMaintenanceTask?.cancel()
        stopPersistentMusic(sendRestorePackets: true, reason: "firmware maintenance started")
        firmwareMaintenanceActive = true
        routeGuidance.stop(reason: "HUD firmware maintenance Wi-Fi")
        nowPlaying.stop(reason: "HUD firmware maintenance Wi-Fi")
        mainVideo.stop(reason: "HUD firmware maintenance Wi-Fi")
        enableHUDWiFiExposure()
        logger.log("HUD MAINT", "Starting boot-animation maintenance: stock 5GHz force=false mode 5")

        let ssid = hudWiFiExpectedSSID
        firmwareMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(5400))
            guard !Task.isCancelled, self.firmwareMaintenanceActive,
                  self.bluetooth.state == .connected else { return }
            self.maintenance.status = "HUD AP ready. Join \(ssid) (password 87654321) in iPhone Wi-Fi Settings, then return and tap Reconnect ADB."
            // Try ADB once in case iOS already re-associated with the remembered HUD network.
            do {
                try await self.maintenance.connectADB(retries: 2)
            } catch {
                self.maintenance.lastError = nil
                self.maintenance.status = "HUD AP ready. Join \(ssid) (password 87654321) in iPhone Wi-Fi Settings, then return and tap Reconnect ADB."
                self.logger.log("HUD MAINT", "Initial ADB probe waiting for manual HUD Wi-Fi join")
            }
            self.firmwareMaintenanceTask = nil
        }
    }

    func reconnectFirmwareMaintenanceADB() {
        guard firmwareMaintenanceActive else { return }
        firmwareMaintenanceTask?.cancel()
        firmwareMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.maintenance.connectADB(retries: 4)
            } catch {
                self.maintenance.lastError = error.localizedDescription
                self.maintenance.status = "ADB reconnect failed: \(error.localizedDescription)"
                self.logger.log("HUD MAINT", "Reconnect failed: \(error.localizedDescription)")
            }
            self.firmwareMaintenanceTask = nil
        }
    }

    func exitFirmwareMaintenance() {
        firmwareMaintenanceTask?.cancel()
        firmwareMaintenanceTask = nil
        maintenance.disconnectADB()
        firmwareMaintenanceActive = false
        disableHUDWiFiExposure(reason: "exit firmware maintenance")
        logger.log("HUD MAINT", "Exited maintenance; restoring normal HUD mode and U2W polling")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard let self, self.bluetooth.state == .connected, !self.firmwareMaintenanceActive else { return }
            self.routeGuidance.start(reason: "firmware maintenance ended")
            self.nowPlaying.start(reason: "firmware maintenance ended")
            self.mainVideo.start(reason: "firmware maintenance ended")
        }
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
        navigation.showCurrentTurnText = settings.navigationShowCurrentTurnText
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

    // MARK: - Persistent stock music renderer experiment

    func startPersistentMusic(mini: Bool) {
        guard bluetooth.state == .connected else {
            persistentMusicStatus = "Connect the HUD over BLE first"
            return
        }
        guard !firmwareMaintenanceActive else {
            persistentMusicStatus = "Exit HUD Firmware Maintenance first"
            return
        }

        persistentMusicTask?.cancel()
        persistentMusicActive = true
        persistentMusicMini = mini
        persistentMusicStatus = mini
            ? "Persistent mini music active • reassert every 5 s"
            : "Persistent full music active • reassert every 5 s"

        musicFilterInitialized = true
        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: true),
            label: "Persistent music → native filter ON"
        )
        bluetooth.enqueue(
            HudCommands.widgetsMiniState(mini),
            label: "Persistent music → HUD mini state \(mini ? "ON" : "OFF")"
        )
        sendPersistentMusicFrame(reason: "start")

        persistentMusicTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.persistentMusicRefreshInterval)
                guard !Task.isCancelled,
                      self.persistentMusicActive,
                      self.bluetooth.state == .connected,
                      !self.firmwareMaintenanceActive else { break }

                if self.persistentMusicMini {
                    // Keep the stock mini layout selected during this explicit
                    // experiment. This command is global to the stock HUD UI.
                    self.bluetooth.enqueue(
                        HudCommands.widgetsMiniState(true),
                        label: "Persistent music → mini-state reassert"
                    )
                }
                self.sendPersistentMusicFrame(reason: "5 s keepalive")
            }
        }

        logger.log(
            "HUD PERSISTENT MUSIC",
            "started renderer=\(mini ? "mini" : "full") interval=5s stock-timeout=\(settings.notificationExposureSeconds)s"
        )
    }

    func stopPersistentMusic() {
        stopPersistentMusic(sendRestorePackets: true, reason: "manual stop")
    }

    private func stopPersistentMusic(sendRestorePackets: Bool, reason: String) {
        persistentMusicTask?.cancel()
        persistentMusicTask = nil
        let wasActive = persistentMusicActive
        let wasMini = persistentMusicMini
        persistentMusicActive = false
        persistentMusicMini = false
        persistentMusicStatus = "Persistent music stopped"

        if sendRestorePackets, bluetooth.state == .connected {
            if wasMini {
                bluetooth.enqueue(
                    HudCommands.widgetsMiniState(false),
                    label: "Persistent music → restore normal HUD state"
                )
            }
            bluetooth.enqueue(
                HudCommands.musicNotificationFilter(enabled: settings.notifyMusic),
                label: "Persistent music → restore Music filter \(settings.notifyMusic ? "ON" : "OFF")"
            )
            musicFilterInitialized = settings.notifyMusic
        }

        if wasActive {
            logger.log("HUD PERSISTENT MUSIC", "stopped reason=\(reason)")
        }
    }

    private func sendPersistentMusicFrame(reason: String) {
        guard persistentMusicActive, bluetooth.state == .connected else { return }

        let artist = nowPlaying.artist.isEmpty ? "HUDWAY" : nowPlaying.artist
        let track = nowPlaying.title == "No CarPlay media" || nowPlaying.title.isEmpty
            ? "Persistent Music Test"
            : nowPlaying.title

        bluetooth.enqueue(
            HudCommands.musicNotification(artist: artist, track: track),
            label: "Persistent music → \(artist) — \(track)"
        )
        persistentMusicStatus = "\(persistentMusicMini ? "Mini" : "Full") • \(artist) — \(track)"
        logger.log(
            "HUD PERSISTENT MUSIC",
            "reassert reason=\(reason) renderer=\(persistentMusicMini ? "mini" : "full") artist=\(artist) track=\(track)"
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
        if hudU2WLiveRelayActive {
            // Mode 6 emits a firmware/session hello on this HUD. Rehydrating Freeride /
            // Navigation profiles during an active KivicCast STA session overrides the
            // casting state and was observed to collapse a valid stream after ~1 second.
            logger.log("HUD REHYDRATE", "Suppressed during live U2W relay reason=\(reason)")
            return
        }
        hudRehydrateTask?.cancel()
        hudReassertTask?.cancel()
        timeWeatherColdOffSyncTask?.cancel()
        timeWeatherColdOffSyncTask = nil

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
                self.scheduleTimeWeatherColdOffSynchronization(reason: reason)
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
        applyDisplayCalibration()
        applyColorTheme()
        applyNotificationSettings()
        obd.hudDidBecomeReady()
        restoreDashboardOperatingMode(reason: "phase 2 persisted state / \(reason)")
        // Important ordering: dashboard/profile packets can restore firmware's
        // default bottom panel, so the persisted time/weather state must follow.
        applyTimeWeather()
        ambientLight.rehydrateHUDState()
        speedEngine.primeRectangularStyle()
        speedEngine.rehydrateHUDState()


        musicFilterInitialized = false
        pushNowPlayingMetadataToHUD()

        logger.log(
            "HUD REHYDRATE",
            "PHASE 2 END brightness=\(settings.brightness) autoBrightness=\(settings.autoBrightness) " +
            "timeWeather=\(settings.showTimeWeather) scale=\(settings.displayScaleAdjustment) perspective=\(settings.displayPerspectiveAdjustment) " +
            "color=\(settings.colorTheme.rawValue) OBDauto=\(obd.autoConnect) " +
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
        applyDisplayCalibration()
        applyColorTheme()
        obd.applyWidgetSelection()
        restoreDashboardOperatingMode(reason: "phase 3 display reassert / \(reason)")
        // Final authoritative packet after dashboard reconstruction. The
        // onDashboardProfileApplied callback also performs one delayed reassert.
        applyTimeWeather()
        ambientLight.rehydrateHUDState()
        speedEngine.rehydrateHUDState()


        logger.log("HUD REHYDRATE", "PHASE 3 display reassert END")
    }

}