import Foundation

enum HudManeuver: String, CaseIterable, Identifiable, Codable {
    case straight, slightRight, right, sharpRight, slightLeft, left, sharpLeft, uTurn
    case keepRight, keepLeft, exitRight, exitLeft, roundabout, destination

    var id: String { rawValue }

    var label: String {
        switch self {
        case .straight: "Straight"
        case .slightRight: "Slight right"
        case .right: "Right"
        case .sharpRight: "Sharp right"
        case .slightLeft: "Slight left"
        case .left: "Left"
        case .sharpLeft: "Sharp left"
        case .uTurn: "U-turn"
        case .keepRight: "Keep right"
        case .keepLeft: "Keep left"
        case .exitRight: "Exit right"
        case .exitLeft: "Exit left"
        case .roundabout: "Roundabout"
        case .destination: "Destination"
        }
    }

    var type: Int {
        switch self {
        case .exitRight, .exitLeft: 7
        case .keepRight, .keepLeft: 8
        case .roundabout: 11
        case .destination: 17
        default: 2
        }
    }

    var direction: Int {
        switch self {
        case .sharpRight: 1
        case .right, .exitRight, .roundabout: 2
        case .slightRight, .keepRight: 3
        case .straight, .destination: 4
        case .slightLeft, .keepLeft: 5
        case .left, .exitLeft: 6
        case .sharpLeft: 7
        case .uTurn: 8
        }
    }

    var symbol: String {
        switch self {
        case .straight: "arrow.up"
        case .slightRight, .keepRight: "arrow.up.right"
        case .right, .exitRight: "arrow.turn.up.right"
        case .sharpRight: "arrow.right"
        case .slightLeft, .keepLeft: "arrow.up.left"
        case .left, .exitLeft: "arrow.turn.up.left"
        case .sharpLeft: "arrow.left"
        case .uTurn: "arrow.uturn.left"
        case .roundabout: "arrow.triangle.2.circlepath"
        case .destination: "flag.checkered"
        }
    }
}

struct NavigationInstruction: Equatable, Codable {
    var maneuver: HudManeuver
    var distanceMeters: Int
    var primaryText: String
    var streetName: String
    /// Exact distance text from the source navigation UI, e.g. "80 ft" or
    /// "0.4 mi". HUD protocol still uses distanceMeters internally.
    var displayDistanceText: String = ""
    var currentStreet: String = ""
    var exitNumber: Int? = nil
}

protocol NavigationSource {
    var name: String { get }
    func start() async
    func stop() async
}

/// Fresh semantic route context from the CarPlay Route Guidance exporter.
///
/// This intentionally contains no posted-speed value. The speed-limit engine
/// may use it only to decide which nearby OSM/Philadelphia road is most likely
/// to be the vehicle's current road; the legal limit still comes from map/GIS
/// speed data.
struct CarPlayRouteContext: Equatable {
    var source: String
    var sequence: Int
    var routeState: Int
    var currentRoad: String
    var nextRoad: String
    var distanceToManeuverMeters: Int
    var receivedAt: Date

    var isRerouting: Bool { routeState == 5 }
    /// State 3 was observed during route calculation/recalculation; state 5 is
    /// explicit rerouting. Both should weaken semantic road assistance.
    var isRouteTransition: Bool { routeState == 3 || routeState == 5 }
}
