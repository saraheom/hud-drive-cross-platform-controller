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

    init() {
        let logger = LogManager()
        self.logger = logger
        let bluetooth = HudBluetoothManager(logger: logger)
        self.bluetooth = bluetooth
        let navigation = HudNavigationController(bluetooth: bluetooth, logger: logger)
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