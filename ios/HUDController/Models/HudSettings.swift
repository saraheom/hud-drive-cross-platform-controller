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
        .init(name: "Freeride", left: "Distance", center: "Simple", right: "TripTime", navigationLayout: false),
        .init(name: "Navigation", left: "Distance", center: "Navigation", right: "ETA", navigationLayout: true),
        .init(name: "Minimal", left: "Empty", center: "Simple", right: "Empty", navigationLayout: false),
        .init(name: "Driving stats", left: "AvgSpeedo", center: "Digits", right: "MaxSpeedo", navigationLayout: false),
    ]
}




enum HudLanePlacementMode: String, CaseIterable, Identifiable {
    case centerNative
    case rightNavigationProbe
    case rightNaviMiniProbe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centerNative: return "Center (stock)"
        case .rightNavigationProbe: return "Right probe: Navigation"
        case .rightNaviMiniProbe: return "Right probe: NaviMini"
        }
    }

    var rightWidgetName: String? {
        switch self {
        case .centerNative: return nil
        case .rightNavigationProbe: return "Navigation"
        case .rightNaviMiniProbe: return "NaviMini"
        }
    }
}
enum HudLaneGuidanceMode: String, CaseIterable, Identifiable {
    case off
    case nearTurn
    case persistent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .nearTurn: return "Near turn"
        case .persistent: return "Persistent"
        }
    }
}

@MainActor
@Observable
final class HudSettings {
    private let defaults = UserDefaults.standard

    var autoBrightness: Bool { didSet { defaults.set(autoBrightness, forKey: "HUD.Settings.autoBrightness") } }
    var brightness: Int { didSet { defaults.set(brightness, forKey: "HUD.Settings.brightness") } }
    var showTimeWeather: Bool { didSet { defaults.set(showTimeWeather, forKey: "HUD.Settings.showTimeWeather") } }
    var minimizeWidgets: Bool { didSet { defaults.set(minimizeWidgets, forKey: "HUD.Settings.minimizeWidgets") } }
    /// Original HUDWAY Advanced-screen seeker values (0...100).
    /// They are converted to firmware Float32 values only when transmitted.
    var displayScaleAdjustment: Int { didSet { defaults.set(displayScaleAdjustment, forKey: "HUD.Settings.displayScaleAdjustment") } }
    var displayPerspectiveAdjustment: Int { didSet { defaults.set(displayPerspectiveAdjustment, forKey: "HUD.Settings.displayPerspectiveAdjustment") } }

    var displayScaleWireValue: Float {
        Float(max(0, min(100, displayScaleAdjustment))) * 0.2 / 100.0
    }

    var displayPerspectiveWireValue: Float {
        Float(max(0, min(100, displayPerspectiveAdjustment))) * 0.1 / 100.0
    }
    var colorTheme: HudColorTheme {
        didSet { defaults.set(colorTheme.rawValue, forKey: "HUD.Settings.colorTheme") }
    }
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
    var navigationShowCurrentStreet: Bool { didSet { defaults.set(navigationShowCurrentStreet, forKey: "HUD.Settings.navigationShowCurrentStreet") } }
    var navigationShowCurrentTurnText: Bool { didSet { defaults.set(navigationShowCurrentTurnText, forKey: "HUD.Settings.navigationShowCurrentTurnText") } }
    var laneGuidanceMode: HudLaneGuidanceMode { didSet { defaults.set(laneGuidanceMode.rawValue, forKey: "HUD.Settings.laneGuidanceMode") } }
    var laneGuidanceDistanceMiles: Double { didSet { defaults.set(laneGuidanceDistanceMiles, forKey: "HUD.Settings.laneGuidanceDistanceMiles") } }
    var lanePlacementMode: HudLanePlacementMode { didSet { defaults.set(lanePlacementMode.rawValue, forKey: "HUD.Settings.lanePlacementMode") } }

    var notificationExposureSeconds: Int { didSet { defaults.set(notificationExposureSeconds, forKey: "HUD.Settings.notificationExposureSeconds") } }
    var notificationLines: Int { didSet { defaults.set(notificationLines, forKey: "HUD.Settings.notificationLines") } }


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
        func double(_ key: String, default fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
        }

        autoBrightness = bool("HUD.Settings.autoBrightness", default: false)
        brightness = integer("HUD.Settings.brightness", default: 50)
        showTimeWeather = bool("HUD.Settings.showTimeWeather", default: true)
        minimizeWidgets = bool("HUD.Settings.minimizeWidgets", default: false)
        displayScaleAdjustment = min(100, max(0, integer("HUD.Settings.displayScaleAdjustment", default: 0)))
        displayPerspectiveAdjustment = min(100, max(0, integer("HUD.Settings.displayPerspectiveAdjustment", default: 0)))

        let colorName = store.string(forKey: "HUD.Settings.colorTheme") ?? "Red"
        colorTheme = HudColorTheme(rawValue: colorName) ?? .red

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
        navigationShowCurrentStreet = bool("HUD.Settings.navigationShowCurrentStreet", default: true)
        navigationShowCurrentTurnText = bool("HUD.Settings.navigationShowCurrentTurnText", default: true)
        let laneModeRaw = store.string(forKey: "HUD.Settings.laneGuidanceMode") ?? HudLaneGuidanceMode.nearTurn.rawValue
        laneGuidanceMode = HudLaneGuidanceMode(rawValue: laneModeRaw) ?? .nearTurn
        laneGuidanceDistanceMiles = min(1.0, max(0.1, double("HUD.Settings.laneGuidanceDistanceMiles", default: 0.5)))
        let lanePlacementRaw = store.string(forKey: "HUD.Settings.lanePlacementMode") ?? HudLanePlacementMode.centerNative.rawValue
        let restoredLanePlacement = HudLanePlacementMode(rawValue: lanePlacementRaw) ?? .centerNative
        // v90.34.12 retires the physically disproven right-side lane probes from
        // the normal UI. Migrate any persisted probe selection back to stock so
        // ETA cannot remain replaced by an empty right-side widget.
        lanePlacementMode = .centerNative
        if restoredLanePlacement != .centerNative {
            store.set(HudLanePlacementMode.centerNative.rawValue, forKey: "HUD.Settings.lanePlacementMode")
        }

        notificationExposureSeconds = integer("HUD.Settings.notificationExposureSeconds", default: 10)
        notificationLines = integer("HUD.Settings.notificationLines", default: 5)

    }
}
