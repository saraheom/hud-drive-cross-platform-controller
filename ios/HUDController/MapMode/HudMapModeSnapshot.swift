import Foundation

struct HudMapModeSnapshot: Equatable {
    var speedMph: Int
    var speedLimitMph: Int
    var currentRoad: String
    var turningStreet: String
    var maneuver: HudManeuver
    /// Source maneuver text retained so Map Mode can distinguish merge graphics
    /// even when the stock HUD maneuver vocabulary collapses them to straight.
    var maneuverText: String
    var distanceText: String
    var destination: String
    var etaText: String
    var timeLeftText: String
    var laneValues: [Int]
    var routeRoads: [String]
    var hasLiveRoute: Bool


    /// Always-populated styling sample used only inside the customization panel.
    /// It deliberately does not mirror the live HUD preview above the controls: the
    /// latter remains source-faithful and blank when navigation is inactive.
    static let customizationDemo = HudMapModeSnapshot(
        speedMph: 32,
        speedLimitMph: 25,
        currentRoad: "Martin Luther King Jr Dr",
        turningStreet: "Sweetbriar Dr",
        maneuver: .right,
        maneuverText: "Turn right",
        distanceText: "0.4 mi",
        destination: "Demo destination",
        etaText: "6:20 PM",
        timeLeftText: "7 min",
        laneValues: [-4, 1, 3, -2],
        routeRoads: [
            "Martin Luther King Jr Dr",
            "Sweetbriar Dr",
            "Lansdowne Dr",
            "Falls Bridge",
            "Ridge Ave"
        ],
        hasLiveRoute: true
    )

    static let previewFallback = HudMapModeSnapshot(
        speedMph: 37,
        speedLimitMph: 45,
        currentRoad: "N 38th St",
        turningStreet: "Sweetbriar Dr",
        maneuver: .right,
        maneuverText: "Turn right",
        distanceText: "100 ft",
        destination: "Work",
        etaText: "9:05 AM",
        timeLeftText: "1 min",
        laneValues: [-1, -1, 2],
        routeRoads: [
            "Ridge Ave",
            "Calumet St",
            "Martin Luther King Jr Dr",
            "Sweetbriar Dr",
            "Lansdowne Dr",
            "Powelton Ave"
        ],
        hasLiveRoute: false
    )
}
