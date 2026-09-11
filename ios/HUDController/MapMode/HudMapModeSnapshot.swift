import Foundation

struct HudMapModeSnapshot: Equatable {
    var speedMph: Int
    var speedLimitMph: Int
    var currentRoad: String
    var turningStreet: String
    var maneuver: HudManeuver
    var distanceText: String
    var destination: String
    var etaText: String
    var timeLeftText: String
    var laneValues: [Int]
    var routeRoads: [String]
    var hasLiveRoute: Bool

    static let previewFallback = HudMapModeSnapshot(
        speedMph: 37,
        speedLimitMph: 45,
        currentRoad: "N 38th St",
        turningStreet: "Sweetbriar Dr",
        maneuver: .right,
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
