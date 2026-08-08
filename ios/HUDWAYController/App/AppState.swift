import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let logger: LogManager
    let bluetooth: HudwayBluetoothManager
    let navigation: HudwayNavigationController
    let settings = HudwaySettings()

    init() {
        let logger = LogManager()
        self.logger = logger
        let bluetooth = HudwayBluetoothManager(logger: logger)
        self.bluetooth = bluetooth
        self.navigation = HudwayNavigationController(bluetooth: bluetooth, logger: logger)
    }

    func initializeHUD() {
        logger.log("APP", "Initialize HUD requested")
        bluetooth.initializeHUD()
    }

    func applyBrightness() {
        bluetooth.enqueue(HudwayCommands.autoBrightness(settings.autoBrightness), label: "Auto brightness \(settings.autoBrightness)")
        if !settings.autoBrightness {
            bluetooth.enqueue(HudwayCommands.manualBrightness(settings.brightness), label: "Brightness \(settings.brightness)")
        }
    }

    func applyTimeWeather() {
        bluetooth.enqueue(HudwayCommands.timeWeather(settings.showTimeWeather), label: "Time/weather \(settings.showTimeWeather)")
    }

    func applyDashboardPreset() {
        let p = settings.selectedPreset
        bluetooth.enqueue(
            HudwayCommands.dashboard(left: p.left, center: p.center, right: p.right, navigationLayout: p.navigationLayout),
            label: "Dashboard \(p.name)"
        )
    }
}
