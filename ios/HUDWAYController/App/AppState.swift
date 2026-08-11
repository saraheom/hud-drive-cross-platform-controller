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


    func applyNotificationSettings() {
        logger.log("NOTIFICATION", "Applying HUD ANCS notification filter settings")

        bluetooth.enqueue(
            HudwayCommands.notificationSettingsInit(),
            label: "Notification filter init"
        )
        bluetooth.enqueue(
            HudwayCommands.notificationsMasterEnabled(true),
            label: "Notifications master ON"
        )
        bluetooth.enqueue(
            HudwayCommands.notificationTimeout(seconds: settings.notificationExposureSeconds),
            label: "Notification timeout \(settings.notificationExposureSeconds)s"
        )
        bluetooth.enqueue(
            HudwayCommands.notificationLineCount(settings.notificationLines),
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
            (.kakaoTalk, settings.notifyKakaoTalk),
            (.spotify, settings.notifySpotify),
            (.googleMaps, settings.notifyGoogleMaps),
            (.appleMaps, settings.notifyAppleMaps),
            (.waze, settings.notifyWaze)
        ]

        for (kind, enabled) in selections where enabled {
            logger.log(
                "NOTIFICATION FILTER",
                "\(kind.displayName): \(kind.identifiers.joined(separator: ", "))"
            )
            bluetooth.enqueue(
                HudwayCommands.notificationFilter(
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
            HudwayCommands.dashboard(left: p.left, center: p.center, right: p.right, navigationLayout: p.navigationLayout),
            label: "Dashboard \(p.name)"
        )
    }
}
