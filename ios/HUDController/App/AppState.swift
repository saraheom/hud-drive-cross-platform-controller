import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppState {
    let logger: LogManager
    let bluetooth: HudBluetoothManager
    let navigation: HudNavigationController
    let spotify: SpotifyMediaController
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
        self.navigation = HudNavigationController(bluetooth: bluetooth, logger: logger)
        let spotify = SpotifyMediaController(logger: logger)
        self.spotify = spotify
        let obd = HudOBDController(bluetooth: bluetooth, logger: logger)
        self.obd = obd
        let speedEngine = OriginalSpeedLimitEngine(bluetooth: bluetooth, logger: logger)
        self.speedEngine = speedEngine
        let ambientLight = AmbientLightMonitor(bluetooth: bluetooth, logger: logger)
        self.ambientLight = ambientLight
        if #available(iOS 27.0, *) {
            self.externalCapture27 = ExternalNavigationCapture(logger: logger, navigation: self.navigation)
        }

        spotify.onTrackChanged = { [weak self] artist, track in
            self?.pushSpotifyMetadataToHUD(artist: artist, track: track)
        }

        bluetooth.onTransportReady = { [weak self] in
            self?.scheduleHUDRehydration(reason: "BLE transport ready")
        }

        bluetooth.onHUDSessionReset = { [weak self] in
            self?.scheduleHUDRehydration(reason: "HUD firmware hello / physical session reset")
        }

        bluetooth.onTransportDisconnected = { [weak self] in
            guard let self else { return }
            self.hudRehydrateTask?.cancel()
            self.hudRehydrateTask = nil
            self.hudReassertTask?.cancel()
            self.hudReassertTask = nil
            self.obd.transportDisconnected()
            if #available(iOS 27.0, *),
               let capture = self.externalCapture27 as? ExternalNavigationCapture {
                // Do not stop ScreenCaptureKit; only mark HUD delivery unarmed.
                capture.hudSessionDidReset(reason: "HUD BLE transport disconnected")
            }
            self.logger.log("HUD SESSION", "BLE transport disconnected; preserved iPhone-side settings/capture")
        }
    }

    func initializeHUD() {
        logger.log("APP", "Initialize HUD requested")
        bluetooth.initializeHUD()
    }

    func applyBrightness() {
        bluetooth.enqueue(HudCommands.autoBrightness(settings.autoBrightness), label: "Auto brightness \(settings.autoBrightness)")
        if !settings.autoBrightness {
            bluetooth.enqueue(HudCommands.manualBrightness(settings.brightness), label: "Brightness \(settings.brightness)")
        }
    }

    func applyTimeWeather() {
        bluetooth.enqueue(HudCommands.timeWeather(settings.showTimeWeather), label: "Time/weather \(settings.showTimeWeather)")
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
        bluetooth.enqueue(
            HudCommands.dashboard(left: p.left, center: p.center, right: p.right, navigationLayout: p.navigationLayout),
            label: "Dashboard \(p.name)"
        )
    }

    func sendNativeMusicTest() {
        pushSpotifyMetadataToHUD(
            artist: spotify.artistName.isEmpty ? "Kenshi Yonezu" : spotify.artistName,
            track: spotify.trackTitle == "No Spotify track" ? "Flamingo" : spotify.trackTitle
        )
    }


    func pushSpotifyMetadataToHUD(artist: String? = nil, track: String? = nil) {
        guard bluetooth.state == .connected else { return }

        let resolvedArtist = artist ?? spotify.artistName
        let resolvedTrack = track ?? spotify.trackTitle
        guard !resolvedArtist.isEmpty,
              !resolvedTrack.isEmpty,
              resolvedTrack != "No Spotify track" else { return }

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
        logger.log("HUD REHYDRATE", "PHASE 1 base END")
    }

    private func rehydrateUserHUD(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 2 persisted state BEGIN")

        applyBrightness()
        applyTimeWeather()
        applyNotificationSettings()
        obd.hudDidBecomeReady()
        ambientLight.rehydrateHUDState()
        speedEngine.rehydrateHUDState()

        if #available(iOS 27.0, *),
           let capture = externalCapture27 as? ExternalNavigationCapture {
            capture.hudSessionDidReset(reason: reason)
            capture.requestAutomaticStartIfDesired()
        }

        musicFilterInitialized = false
        pushSpotifyMetadataToHUD()

        logger.log(
            "HUD REHYDRATE",
            "PHASE 2 END brightness=\(settings.brightness) autoBrightness=\(settings.autoBrightness) " +
            "timeWeather=\(settings.showTimeWeather) OBDauto=\(obd.autoConnect) " +
            "speedLimit=\(speedEngine.showSpeedLimit) tolerance=+\(speedEngine.speedTolerance)mph"
        )
    }

    private func reassertDisplayCriticalState(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 3 display reassert BEGIN reason=\(reason)")

        // These are deliberately resent after firmware startup so the HUD's
        // own boot defaults cannot win. Rectangular speed-limit style is
        // hard-coded inside the speed engine/command path.
        applyBrightness()
        applyTimeWeather()
        obd.applyWidgetSelection()
        ambientLight.rehydrateHUDState()
        speedEngine.rehydrateHUDState()

        if #available(iOS 27.0, *),
           let capture = externalCapture27 as? ExternalNavigationCapture {
            capture.hudSessionDidReset(reason: "phase 3 display reassert")
        }

        logger.log("HUD REHYDRATE", "PHASE 3 display reassert END")
    }

}