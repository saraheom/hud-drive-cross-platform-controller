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
final class HudwaySettings {
    var autoBrightness = false
    var brightness = 50
    var showTimeWeather = true
    var minimizeWidgets = false
    var selectedPreset = DashboardPreset.presets[0]

    var notifyCalls = true
    var notifyMessages = true
    var notifyCalendar = true
    var notifyGmail = true
    var notifyWeChat = true
    var notifyKakaoTalk = true
    var notifySpotify = true
    var notificationExposureSeconds = 10
    var notificationLines = 5
}
