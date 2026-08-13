import Foundation
import Observation

enum HudTextProbeRoute: String, CaseIterable, Identifiable {
    case phoneName
    case nativeMusic
    case genericNotification
    case navigationText
    case dashboardUnknownToken

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .phoneName: return "Phone-name text"
        case .nativeMusic: return "Native music packet"
        case .genericNotification: return "Notification category"
        case .navigationText: return "Navigation text renderer"
        case .dashboardUnknownToken: return "Unknown dashboard token"
        }
    }
}

@MainActor
@Observable
final class HudTextRendererProbe {
    var title: String {
        didSet { UserDefaults.standard.set(title, forKey: "HUD.TextProbe.title") }
    }
    var message: String {
        didSet { UserDefaults.standard.set(message, forKey: "HUD.TextProbe.message") }
    }
    var packageName: String {
        didSet { UserDefaults.standard.set(packageName, forKey: "HUD.TextProbe.packageName") }
    }
    var notificationCategory: Int {
        didSet { UserDefaults.standard.set(notificationCategory, forKey: "HUD.TextProbe.category") }
    }
    var selectedRoute: HudTextProbeRoute {
        didSet { UserDefaults.standard.set(selectedRoute.rawValue, forKey: "HUD.TextProbe.route") }
    }

    private(set) var status = "Ready"
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger

        let d = UserDefaults.standard
        self.title = d.string(forKey: "HUD.TextProbe.title") ?? "TEST ARTIST"
        self.message = d.string(forKey: "HUD.TextProbe.message") ?? "TEST TRACK"
        self.packageName = d.string(forKey: "HUD.TextProbe.packageName") ?? "com.kivic.music"
        self.notificationCategory = d.object(forKey: "HUD.TextProbe.category") == nil
            ? 12
            : d.integer(forKey: "HUD.TextProbe.category")
        self.selectedRoute = d.string(forKey: "HUD.TextProbe.route")
            .flatMap(HudTextProbeRoute.init(rawValue:))
            ?? .nativeMusic
    }

    func sendSelected() {
        guard bluetooth.state == .connected else {
            status = "HUD not connected"
            logger.log("TEXT PROBE", "Skipped: HUD not connected")
            return
        }

        switch selectedRoute {
        case .phoneName:
            bluetooth.enqueue(
                HudCommands.phoneName("\(title) | \(message)"),
                label: "Text probe → Phone name"
            )
            status = "Sent phone-name text"

        case .nativeMusic:
            bluetooth.enqueue(
                HudCommands.musicNotificationFilter(enabled: true),
                label: "Text probe → Enable music filter"
            )
            bluetooth.enqueue(
                HudCommands.musicNotification(
                    artist: title,
                    track: message,
                    packageName: packageName
                ),
                label: "Text probe → Native music"
            )
            status = "Sent native music text"

        case .genericNotification:
            bluetooth.enqueue(
                HudCommands.notificationSettingsInit(),
                label: "Text probe → Notification init"
            )
            bluetooth.enqueue(
                HudCommands.notificationsMasterEnabled(true),
                label: "Text probe → Notifications master ON"
            )
            bluetooth.enqueue(
                HudCommands.notificationFilter(
                    enabled: true,
                    textColor: -1,
                    icon: 0,
                    identifiers: [packageName]
                ),
                label: "Text probe → Generic notification filter"
            )
            bluetooth.enqueue(
                HudCommands.textNotificationProbe(
                    category: notificationCategory,
                    packageName: packageName,
                    title: title,
                    message: message
                ),
                label: "Text probe → Notification category \(notificationCategory)"
            )
            status = "Sent notification category \(notificationCategory)"

        case .navigationText:
            bluetooth.enqueue(
                HudCommands.navigationState(true),
                label: "Text probe → Navigation ON"
            )
            bluetooth.enqueue(
                HudCommands.persistentNavigationTextProbe(
                    title: title,
                    detail: message
                ),
                label: "Text probe → Persistent navigation text"
            )
            status = "Sent through navigation text renderer"

        case .dashboardUnknownToken:
            // The dashboard packet itself contains arbitrary UTF strings, but
            // prior experiments indicate firmware resolves them as widget IDs.
            // This deliberately probes whether a raw token can ever render as
            // text. Known expectation: unsupported token -> blank/ignored.
            bluetooth.enqueue(
                HudCommands.dashboard(
                    left: title,
                    center: "Simple",
                    right: message,
                    navigationLayout: false
                ),
                label: "Text probe → Raw dashboard UTF tokens"
            )
            status = "Sent raw dashboard strings"
        }

        logger.log(
            "TEXT PROBE",
            "route=\(selectedRoute.rawValue) category=\(notificationCategory) package=\(packageName) title=\(title) message=\(message)"
        )
    }

    func sweepNotificationCategories() {
        guard bluetooth.state == .connected else {
            status = "HUD not connected"
            return
        }

        bluetooth.enqueue(
            HudCommands.notificationSettingsInit(),
            label: "Text sweep → Notification init"
        )
        bluetooth.enqueue(
            HudCommands.notificationsMasterEnabled(true),
            label: "Text sweep → Notifications master ON"
        )
        bluetooth.enqueue(
            HudCommands.notificationFilter(
                enabled: true,
                textColor: -1,
                icon: 0,
                identifiers: [packageName]
            ),
            label: "Text sweep → Filter"
        )

        for category in 0...15 {
            bluetooth.enqueue(
                HudCommands.textNotificationProbe(
                    category: category,
                    packageName: packageName,
                    title: "CAT \(category) \(title)",
                    message: message
                ),
                label: "Text sweep → category \(category)"
            )
        }

        status = "Queued categories 0–15"
        logger.log("TEXT PROBE", "Queued notification category sweep 0...15")
    }

    func useCurrentSpotify(spotify: SpotifyMediaController) {
        if !spotify.artistName.isEmpty {
            title = spotify.artistName
        }
        if !spotify.trackTitle.isEmpty,
           spotify.trackTitle != "No Spotify track" {
            message = spotify.trackTitle
        }
        status = "Loaded current Spotify metadata"
    }

    func restoreNormalPhoneName() {
        guard bluetooth.state == .connected else { return }
        bluetooth.enqueue(
            HudCommands.phoneName("HUD Controller"),
            label: "Restore normal phone name"
        )
        status = "Restored normal phone name"
    }
}
