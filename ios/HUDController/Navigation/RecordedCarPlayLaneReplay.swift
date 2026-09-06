import Foundation

/// v90.34.4 parked-HUD replay fixtures reconstructed from the user's physical
/// U2W Route Guidance captures. The fixture contains only data that was already
/// observed on the wire; it never contacts the CarPlay adapter and never writes
/// to HUD firmware.
enum RecordedCarPlayLaneReplay {
    enum Route: String, CaseIterable, Identifiable {
        case appleMaps
        case googleMaps

        var id: String { rawValue }

        var title: String {
            switch self {
            case .appleMaps: return "Apple Maps • recorded 0x5204"
            case .googleMaps: return "Google Maps • recorded 0x5204"
            }
        }

        var captureLabel: String {
            switch self {
            case .appleMaps: return "U2W v8.5 physical capture"
            case .googleMaps: return "U2W v8.6 physical capture"
            }
        }

        var steps: [Step] {
            switch self {
            case .appleMaps: return appleSteps
            case .googleMaps: return googleSteps
            }
        }
    }

    struct Lane: Equatable {
        /// Signed CarPlay direction angles recovered from nested 0x5204 TLVs.
        /// -90/-45 = left family, 0 = straight, +45/+90 = right family.
        var angles: [Int]
        var recommended: Bool

        var nativeType: HudCommands.NativeLaneType {
            let hasLeft = angles.contains(where: { $0 < 0 })
            let hasStraight = angles.contains(0)
            let hasRight = angles.contains(where: { $0 > 0 })

            if hasLeft && hasStraight { return .straightLeft }
            if hasRight && hasStraight { return .straightRight }
            if hasLeft { return .left }
            if hasRight { return .right }
            return .straight
        }

        var nativeLane: HudCommands.NativeLane {
            .init(type: nativeType, recommended: recommended)
        }

        var angleText: String {
            angles.map { value in
                if value > 0 { return "+\(value)°" }
                return "\(value)°"
            }.joined(separator: "/")
        }
    }

    struct Step: Identifiable, Equatable {
        let id: String
        let source: String
        let captureRecord: Int
        let laneGroupIndex: Int
        let currentRoad: String
        let maneuverDescription: String
        let carPlayManeuverType: Int
        let instruction: NavigationInstruction
        let lanes: [Lane]

        var nativeLanes: [HudCommands.NativeLane] { lanes.map(\.nativeLane) }
        var hudValues: [Int32] { nativeLanes.map(\.wireValue) }

        var laneAngleSummary: String {
            lanes.enumerated().map { index, lane in
                "L\(index + 1) \(lane.angleText)\(lane.recommended ? " ★" : "")"
            }.joined(separator: "  •  ")
        }

        var hudValueSummary: String {
            hudValues.map(String.init).joined(separator: ", ")
        }

        var displayTitle: String {
            "Record \(captureRecord) • lane group \(laneGroupIndex)"
        }
    }

    // U2W_RGD_V85_DUMP physical Apple Maps lane messages.
    // At records 170...175 the Route Guidance current/legacy-next maneuver was
    // index 5: "To Kelly Dr and Lincoln Dr", current road Powelton Ave, and
    // distance-to-maneuver 367 m / 0.2 mi. Record 278 was N 33rd St -> Mantua Ave.
    private static let appleSteps: [Step] = [
        makeStep(
            id: "apple-170", source: "Apple Maps", record: 170, group: 0,
            currentRoad: "Powelton Ave", description: "To Kelly Dr and Lincoln Dr",
            carPlayType: 8, maneuver: .exitRight, primary: "Take exit right",
            street: "Kelly Dr", distance: 367, displayDistance: "0.2 mi",
            lanes: [
                .init(angles: [-45, 0], recommended: false),
                .init(angles: [0], recommended: true),
                .init(angles: [0], recommended: false),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "apple-171", source: "Apple Maps", record: 171, group: 1,
            currentRoad: "Powelton Ave", description: "To Kelly Dr and Lincoln Dr",
            carPlayType: 8, maneuver: .exitRight, primary: "Take exit right",
            street: "Kelly Dr", distance: 367, displayDistance: "0.2 mi",
            lanes: [
                .init(angles: [-45], recommended: false),
                .init(angles: [-45], recommended: true),
                .init(angles: [45], recommended: false),
                .init(angles: [45], recommended: false),
            ]
        ),
        makeStep(
            id: "apple-172", source: "Apple Maps", record: 172, group: 2,
            currentRoad: "Powelton Ave", description: "To Kelly Dr and Lincoln Dr",
            carPlayType: 8, maneuver: .exitRight, primary: "Take exit right",
            street: "Kelly Dr", distance: 367, displayDistance: "0.2 mi",
            lanes: [
                .init(angles: [0], recommended: false),
                .init(angles: [0], recommended: false),
                .init(angles: [45], recommended: true),
            ]
        ),
        makeStep(
            id: "apple-173", source: "Apple Maps", record: 173, group: 3,
            currentRoad: "Powelton Ave", description: "To Kelly Dr and Lincoln Dr",
            carPlayType: 8, maneuver: .exitRight, primary: "Take exit right",
            street: "Kelly Dr", distance: 367, displayDistance: "0.2 mi",
            lanes: [
                .init(angles: [-45], recommended: true),
                .init(angles: [-45], recommended: false),
                .init(angles: [45], recommended: false),
            ]
        ),
        makeStep(
            id: "apple-174", source: "Apple Maps", record: 174, group: 4,
            currentRoad: "Powelton Ave", description: "To Kelly Dr and Lincoln Dr",
            carPlayType: 8, maneuver: .exitRight, primary: "Take exit right",
            street: "Kelly Dr", distance: 367, displayDistance: "0.2 mi",
            lanes: [
                .init(angles: [-45], recommended: true),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "apple-175", source: "Apple Maps", record: 175, group: 5,
            currentRoad: "Powelton Ave", description: "To Kelly Dr and Lincoln Dr",
            carPlayType: 8, maneuver: .exitRight, primary: "Take exit right",
            street: "Kelly Dr", distance: 367, displayDistance: "0.2 mi",
            lanes: [
                .init(angles: [0, -45], recommended: true),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "apple-278", source: "Apple Maps", record: 278, group: 0,
            currentRoad: "N 33rd St", description: "Mantua Ave",
            carPlayType: 1, maneuver: .left, primary: "Turn left",
            street: "Mantua Ave", distance: 493, displayDistance: "0.3 mi",
            lanes: [
                .init(angles: [-90], recommended: false),
                .init(angles: [-90, 0], recommended: false),
                .init(angles: [0], recommended: true),
                .init(angles: [90], recommended: false),
            ]
        ),
    ]

    // U2W_DATA_V86_DUMP physical Google Maps lane messages. The first four
    // records were associated with the captured US-1 N / Roosevelt maneuver;
    // records 132...134 followed the captured route refresh toward River Ridge Ct.
    private static let googleSteps: [Step] = [
        makeStep(
            id: "google-115", source: "Google Maps", record: 115, group: 0,
            currentRoad: "Ridge Ave", description: "US-1 N",
            carPlayType: 13, maneuver: .keepLeft, primary: "Keep left",
            street: "Roosevelt Bl", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90], recommended: true),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "google-116", source: "Google Maps", record: 116, group: 1,
            currentRoad: "Ridge Ave", description: "US-1 N",
            carPlayType: 13, maneuver: .keepLeft, primary: "Keep left",
            street: "Roosevelt Bl", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90], recommended: true),
                .init(angles: [0], recommended: false),
                .init(angles: [0], recommended: false),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "google-117", source: "Google Maps", record: 117, group: 2,
            currentRoad: "Ridge Ave", description: "US-1 N",
            carPlayType: 13, maneuver: .keepLeft, primary: "Keep left",
            street: "Roosevelt Bl", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90], recommended: true),
                .init(angles: [0, 90], recommended: false),
            ]
        ),
        makeStep(
            id: "google-118", source: "Google Maps", record: 118, group: 3,
            currentRoad: "Ridge Ave", description: "US-1 N",
            carPlayType: 13, maneuver: .keepLeft, primary: "Keep left",
            street: "Roosevelt Bl", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90, 0], recommended: true),
                .init(angles: [45], recommended: false),
            ]
        ),
        makeStep(
            id: "google-132", source: "Google Maps", record: 132, group: 0,
            currentRoad: "Ridge Ave", description: "toward River Ridge Ct",
            carPlayType: 11, maneuver: .straight, primary: "Start route toward River Ridge Ct",
            street: "River Ridge Ct", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90], recommended: true),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "google-133", source: "Google Maps", record: 133, group: 1,
            currentRoad: "Ridge Ave", description: "toward River Ridge Ct",
            carPlayType: 11, maneuver: .straight, primary: "Start route toward River Ridge Ct",
            street: "River Ridge Ct", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90], recommended: true),
                .init(angles: [0], recommended: false),
                .init(angles: [0], recommended: false),
                .init(angles: [0], recommended: false),
            ]
        ),
        makeStep(
            id: "google-134", source: "Google Maps", record: 134, group: 2,
            currentRoad: "Ridge Ave", description: "toward River Ridge Ct",
            carPlayType: 11, maneuver: .straight, primary: "Start route toward River Ridge Ct",
            street: "River Ridge Ct", distance: 0, displayDistance: "0 ft",
            lanes: [
                .init(angles: [-90], recommended: true),
                .init(angles: [0], recommended: false),
            ]
        ),
    ]

    private static func makeStep(
        id: String,
        source: String,
        record: Int,
        group: Int,
        currentRoad: String,
        description: String,
        carPlayType: Int,
        maneuver: HudManeuver,
        primary: String,
        street: String,
        distance: Int,
        displayDistance: String,
        lanes: [Lane]
    ) -> Step {
        Step(
            id: id,
            source: source,
            captureRecord: record,
            laneGroupIndex: group,
            currentRoad: currentRoad,
            maneuverDescription: description,
            carPlayManeuverType: carPlayType,
            instruction: NavigationInstruction(
                maneuver: maneuver,
                distanceMeters: distance,
                primaryText: primary,
                streetName: street,
                displayDistanceText: displayDistance,
                currentStreet: currentRoad
            ),
            lanes: lanes
        )
    }
}
