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
        AppShortcut(intent: ToggleAutomaticMapModeIntent(),
                    phrases: ["Toggle HUD Map Mode in \(.applicationName)", "Switch HUD Map Mode with \(.applicationName)"])
        AppShortcut(intent: EnableAutomaticMapModeIntent(),
                    phrases: ["Enable HUD Map Mode in \(.applicationName)"])
        AppShortcut(intent: DisableAutomaticMapModeIntent(),
                    phrases: ["Disable HUD Map Mode in \(.applicationName)"])
    }
}

// v90.35.3.24.33: the Action Button / Back Tap Shortcut updates the desired
// state rather than pretending to run a suspended BLE/video session. If the app
// already has a live AppState, reconcile immediately. Otherwise the preference
// is applied when HUD Controller is active/allowed to restore BLE transport.
@MainActor
final class HUDMapModeShortcutCoordinator {
    static let shared = HUDMapModeShortcutCoordinator()
    weak var activeState: AppState?

    func set(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "HUD.MapMode.autoEnabled")
        activeState?.setAutomaticMapModeEnabled(enabled, reason: "iPhone Shortcut")
    }

    func toggle() {
        let current = UserDefaults.standard.bool(forKey: "HUD.MapMode.autoEnabled")
        set(enabled: !current)
    }
}

struct EnableAutomaticMapModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Enable HUD Map Mode"
    static var description = IntentDescription("Save automatic Map Mode ON and activate it when the HUD is ready.")
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult {
        await HUDMapModeShortcutCoordinator.shared.set(enabled: true)
        return .result()
    }
}

struct DisableAutomaticMapModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Disable HUD Map Mode"
    static var description = IntentDescription("Save automatic Map Mode OFF and use standard Navigation or Free Ride.")
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult {
        await HUDMapModeShortcutCoordinator.shared.set(enabled: false)
        return .result()
    }
}

struct ToggleAutomaticMapModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle HUD Map Mode"
    static var description = IntentDescription("Toggle the saved automatic Map Mode preference using the iPhone Action Button or Back Tap.")
    static let supportedModes: IntentModes = [.background]

    func perform() async throws -> some IntentResult {
        await HUDMapModeShortcutCoordinator.shared.toggle()
        return .result()
    }
}
