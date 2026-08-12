import AppIntents
import Foundation

enum ShortcutRequest: String {
    case connect, initialize, navigationOn, navigationOff, demoRoute, hideTimeWeather, showTimeWeather
}

struct InitializeHUDIntent: AppIntent {
    static var title: LocalizedStringResource = "Initialize HUD"
    static var description = IntentDescription("Open HUD Controller and initialize the connected HUD.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(ShortcutRequest.initialize.rawValue, forKey: "pendingShortcutRequest")
        return .result()
    }
}

struct StartDemoRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Start HUD Demo Route"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(ShortcutRequest.demoRoute.rawValue, forKey: "pendingShortcutRequest")
        return .result()
    }
}

struct NavigationOnIntent: AppIntent {
    static var title: LocalizedStringResource = "HUD Navigation On"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(ShortcutRequest.navigationOn.rawValue, forKey: "pendingShortcutRequest")
        return .result()
    }
}

struct HUDShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: InitializeHUDIntent(),
                    phrases: ["Initialize \(.applicationName)", "Initialize my HUD with \(.applicationName)"])
        AppShortcut(intent: StartDemoRouteIntent(),
                    phrases: ["Start demo route in \(.applicationName)", "Test my HUD navigation in \(.applicationName)"])
        AppShortcut(intent: NavigationOnIntent(),
                    phrases: ["Turn on HUD navigation in \(.applicationName)"])
    }
}
