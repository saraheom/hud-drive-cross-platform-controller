import Foundation
import Observation

struct DashboardPreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let left: String
    let center: String
    let right: String
    let navigationLayout: Bool

    static let presets: [DashboardPreset] = [
        .init(name: "Freeride", left: "Distance", center: "Speedo", right: "TripTime", navigationLayout: false),
        .init(name: "Navigation", left: "Distance", center: "Navigation", right: "ETA", navigationLayout: true),
        .init(name: "Minimal", left: "Empty", center: "Simple", right: "Empty", navigationLayout: false),
        .init(name: "Driving stats", left: "AvgSpeedo", center: "Digits", right: "MaxSpeedo", navigationLayout: false),
    ]
}

@MainActor
@Observable
final class HudSettings {
    private let defaults = UserDefaults.standard

    var autoBrightness: Bool { didSet { defaults.set(autoBrightness, forKey: "HUD.Settings.autoBrightness") } }
    var brightness: Int { didSet { defaults.set(brightness, forKey: "HUD.Settings.brightness") } }
    var showTimeWeather: Bool { didSet { defaults.set(showTimeWeather, forKey: "HUD.Settings.showTimeWeather") } }
    var minimizeWidgets: Bool { didSet { defaults.set(minimizeWidgets, forKey: "HUD.Settings.minimizeWidgets") } }
    var selectedPreset: DashboardPreset {
        didSet { defaults.set(selectedPreset.name, forKey: "HUD.Settings.selectedPreset") }
    }

    var notifyAll: Bool { didSet { defaults.set(notifyAll, forKey: "HUD.Settings.notifyAll") } }
    var notifyCalls: Bool { didSet { defaults.set(notifyCalls, forKey: "HUD.Settings.notifyCalls") } }
    var notifyMessages: Bool { didSet { defaults.set(notifyMessages, forKey: "HUD.Settings.notifyMessages") } }
    var notifyCalendar: Bool { didSet { defaults.set(notifyCalendar, forKey: "HUD.Settings.notifyCalendar") } }
    var notifyGmail: Bool { didSet { defaults.set(notifyGmail, forKey: "HUD.Settings.notifyGmail") } }
    var notifyWeChat: Bool { didSet { defaults.set(notifyWeChat, forKey: "HUD.Settings.notifyWeChat") } }
    var notifyKakaoTalk: Bool { didSet { defaults.set(notifyKakaoTalk, forKey: "HUD.Settings.notifyKakaoTalk") } }
    var notifyMusic: Bool { didSet { defaults.set(notifyMusic, forKey: "HUD.Settings.notifyMusic") } }

    var mediaSpotifyEnabled: Bool { didSet { defaults.set(mediaSpotifyEnabled, forKey: "HUD.Settings.mediaSpotifyEnabled") } }
    var navigationGoogleMapsEnabled: Bool { didSet { defaults.set(navigationGoogleMapsEnabled, forKey: "HUD.Settings.navigationGoogleMapsEnabled") } }
    var navigationAppleMapsEnabled: Bool { didSet { defaults.set(navigationAppleMapsEnabled, forKey: "HUD.Settings.navigationAppleMapsEnabled") } }
    var navigationWazeEnabled: Bool { didSet { defaults.set(navigationWazeEnabled, forKey: "HUD.Settings.navigationWazeEnabled") } }

    var notificationExposureSeconds: Int { didSet { defaults.set(notificationExposureSeconds, forKey: "HUD.Settings.notificationExposureSeconds") } }
    var notificationLines: Int { didSet { defaults.set(notificationLines, forKey: "HUD.Settings.notificationLines") } }

    // Experimental firmware display lab. These settings use hidden protocol
    // commands discovered in the original decompiled Android app.
    var experimentalMusicMirror: Bool {
        didSet { defaults.set(experimentalMusicMirror, forKey: "HUD.Settings.experimentalMusicMirror") }
    }
    var experimentalMusicPosition: Int {
        didSet { defaults.set(experimentalMusicPosition, forKey: "HUD.Settings.experimentalMusicPosition") }
    }
    var experimentalMusicTimeout: Int {
        didSet { defaults.set(experimentalMusicTimeout, forKey: "HUD.Settings.experimentalMusicTimeout") }
    }
    var experimentalMusicLines: Int {
        didSet { defaults.set(experimentalMusicLines, forKey: "HUD.Settings.experimentalMusicLines") }
    }
    var experimentalMusicMini: Bool {
        didSet { defaults.set(experimentalMusicMini, forKey: "HUD.Settings.experimentalMusicMini") }
    }

    init() {
        // Use a local defaults reference during initialization. Referring to
        // the instance property `defaults` from nested helper functions would
        // implicitly use `self` before every stored property is initialized.
        let store = UserDefaults.standard

        func bool(_ key: String, default fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }
        func integer(_ key: String, default fallback: Int) -> Int {
            store.object(forKey: key) == nil ? fallback : store.integer(forKey: key)
        }

        autoBrightness = bool("HUD.Settings.autoBrightness", default: false)
        brightness = integer("HUD.Settings.brightness", default: 50)
        showTimeWeather = bool("HUD.Settings.showTimeWeather", default: true)
        minimizeWidgets = bool("HUD.Settings.minimizeWidgets", default: false)

        let presetName = store.string(forKey: "HUD.Settings.selectedPreset") ?? "Freeride"
        selectedPreset = DashboardPreset.presets.first(where: { $0.name == presetName }) ?? DashboardPreset.presets[0]

        notifyAll = bool("HUD.Settings.notifyAll", default: false)
        notifyCalls = bool("HUD.Settings.notifyCalls", default: true)
        notifyMessages = bool("HUD.Settings.notifyMessages", default: true)
        notifyCalendar = bool("HUD.Settings.notifyCalendar", default: true)
        notifyGmail = bool("HUD.Settings.notifyGmail", default: true)
        notifyWeChat = bool("HUD.Settings.notifyWeChat", default: true)
        notifyKakaoTalk = bool("HUD.Settings.notifyKakaoTalk", default: true)
        notifyMusic = bool("HUD.Settings.notifyMusic", default: true)

        mediaSpotifyEnabled = bool("HUD.Settings.mediaSpotifyEnabled", default: false)
        navigationGoogleMapsEnabled = bool("HUD.Settings.navigationGoogleMapsEnabled", default: false)
        navigationAppleMapsEnabled = bool("HUD.Settings.navigationAppleMapsEnabled", default: false)
        navigationWazeEnabled = bool("HUD.Settings.navigationWazeEnabled", default: false)

        notificationExposureSeconds = integer("HUD.Settings.notificationExposureSeconds", default: 10)
        notificationLines = integer("HUD.Settings.notificationLines", default: 5)

        experimentalMusicMirror = bool("HUD.Settings.experimentalMusicMirror", default: false)
        experimentalMusicPosition = max(0, min(3, integer("HUD.Settings.experimentalMusicPosition", default: 1)))
        experimentalMusicTimeout = max(1, min(3600, integer("HUD.Settings.experimentalMusicTimeout", default: 60)))
        experimentalMusicLines = max(1, min(5, integer("HUD.Settings.experimentalMusicLines", default: 2)))
        experimentalMusicMini = bool("HUD.Settings.experimentalMusicMini", default: false)
    }
}
