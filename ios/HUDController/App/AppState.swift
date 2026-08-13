import Foundation
import Observation

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
        self.speedEngine = OriginalSpeedLimitEngine(bluetooth: bluetooth, logger: logger)
        self.ambientLight = AmbientLightMonitor(bluetooth: bluetooth, logger: logger)
        if #available(iOS 27.0, *) {
            self.externalCapture27 = ExternalNavigationCapture(logger: logger, navigation: self.navigation)
        }

        spotify.onTrackChanged = { [weak self] artist, track in
            self?.pushSpotifyMetadataToHUD(artist: artist, track: track)
        }

        bluetooth.onTransportReady = { [weak obd] in
            obd?.hudDidBecomeReady()
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

        // If an experimental Music side-widget is selected, re-send the
        // corresponding dashboard after metadata updates. This probes whether
        // the firmware has an undocumented Music widget that binds to the
        // MusicNotificationPacket data source.
        if obd.freerideLeft == .spotifyMusicExperimental ||
            obd.freerideRight == .spotifyMusicExperimental {
            obd.applyFreerideWidgets()
        }
        if obd.navigationLeft == .spotifyMusicExperimental ||
            obd.navigationRight == .spotifyMusicExperimental {
            obd.applyNavigationWidgets()
        }
    }

}
