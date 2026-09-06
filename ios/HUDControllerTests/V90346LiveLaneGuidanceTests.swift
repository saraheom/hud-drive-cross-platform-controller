import XCTest
@testable import HUDController

final class V90346LiveLaneGuidanceTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testOldLaneSchemaRemainsOptionalForBackwardCompatibility() throws {
        let json = #"{"version":1,"sequence":1,"source":"Google Maps","routeState":1,"active":true,"currentRoad":"Ridge Ave","destination":"Exponent","estimatedArrivalUnixSeconds":0,"timeRemainingSeconds":0,"distanceRemainingMeters":0,"distanceRemainingText":"","distanceRemainingUnits":0,"distanceToManeuverMeters":321,"distanceToManeuverText":"0.2","distanceToManeuverUnits":0,"currentManeuverIndex":0,"nextManeuverIndex":null,"maneuverCount":1,"laneGuidanceShowing":false,"maneuvers":[{"index":0,"description":"Turn right","type":3,"afterRoad":"Ridge Ave","distanceMeters":321,"displayDistanceText":"0.2","drivingSide":1}]}"#
        let decoded = try JSONDecoder().decode(RouteGuidanceAdapterClient.Snapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.laneGuidance)
        XCTAssertNil(decoded.laneGuidanceIndex)
    }

    func testV87CombinedLaneAnglesStillNormalizeToStockFiveShapeVocabulary() throws {
        let json = #"{"version":1,"sequence":4,"source":"Apple Maps","routeState":1,"active":true,"currentRoad":"Powelton Ave","destination":"Home","estimatedArrivalUnixSeconds":0,"timeRemainingSeconds":0,"distanceRemainingMeters":0,"distanceRemainingText":"","distanceRemainingUnits":0,"distanceToManeuverMeters":367,"distanceToManeuverText":"0.2","distanceToManeuverUnits":0,"currentManeuverIndex":2,"nextManeuverIndex":null,"maneuverCount":3,"laneGuidanceShowing":true,"laneGuidance":{"sequence":7,"maneuverIndex":2,"lanes":[{"index":0,"status":0,"recommended":false,"angles":[-90]},{"index":1,"status":0,"recommended":false,"angles":[-45,0]},{"index":2,"status":2,"recommended":true,"angles":[0]},{"index":3,"status":0,"recommended":false,"angles":[0,45]}]},"maneuvers":[{"index":2,"description":"Continue","type":1,"afterRoad":"Spring Garden St","distanceMeters":367,"displayDistanceText":"0.2","drivingSide":1}]}"#
        let decoded = try JSONDecoder().decode(RouteGuidanceAdapterClient.Snapshot.self, from: Data(json.utf8))
        let guidance = try XCTUnwrap(decoded.laneGuidance)
        let lanes = RouteGuidanceAdapterClient.normalizedNativeLanes(guidance)
        XCTAssertEqual(lanes.map(\.wireValue), [-4, -5, 1, -3])
    }

    func testV88SchemaDecodesActiveSelectorAndComposedEventSeparately() throws {
        let json = #"{"version":2,"sequence":100,"source":"Google Maps","routeState":1,"active":true,"currentRoad":"City Ave","destination":"Home","estimatedArrivalUnixSeconds":0,"timeRemainingSeconds":0,"distanceRemainingMeters":1000,"distanceRemainingText":"0.6","distanceRemainingUnits":0,"distanceToManeuverMeters":321,"distanceToManeuverText":"0.2","distanceToManeuverUnits":0,"currentManeuverIndex":4,"nextManeuverIndex":null,"maneuverCount":8,"laneGuidanceShowing":true,"laneGuidanceIndex":1,"laneGuidance":{"sequence":8,"guidanceEventIndex":1,"maneuverIndex":null,"lanes":[{"index":0,"status":0,"recommended":false,"angles":[0]},{"index":1,"status":2,"recommended":true,"angles":[45]}]},"maneuvers":[{"index":4,"description":"Turn right","type":2,"afterRoad":"Presidential Blvd","distanceMeters":321,"displayDistanceText":"0.2","drivingSide":1}]}"#
        let decoded = try JSONDecoder().decode(RouteGuidanceAdapterClient.Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.laneGuidanceIndex, 1)
        XCTAssertEqual(decoded.laneGuidance?.guidanceEventIndex, 1)
        XCTAssertNil(decoded.laneGuidance?.maneuverIndex)
    }

    func testLiveLaneBindingUsesResolvedV88SelectorAndPostManeuverReassert() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(route.contains("var laneGuidanceIndex: Int?"))
        XCTAssertTrue(route.contains("var guidanceEventIndex: Int?"))
        XCTAssertTrue(route.contains("onManeuverDelivered"))
        XCTAssertTrue(app.contains("receiveResolvedV88LaneGuidance"))
        XCTAssertTrue(app.contains("hidden selector must never"))
        XCTAssertTrue(app.contains("CARPLAY LANE LATCH"))
        XCTAssertTrue(app.contains("activeManeuver == maneuverIndex"))
        XCTAssertTrue(app.contains("post-maneuver reassert"))
    }

    func testLaneFailureCannotOwnOrDisableNormalRouteGuidance() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        let publish = try XCTUnwrap(route.range(of: "private func publishLiveLaneGuidance"))
        let tail = String(route[publish.lowerBound...].prefix(7000))
        XCTAssertFalse(tail.contains("navigation.navigationOff"))
        XCTAssertFalse(tail.contains("navigation.navigationOn"))
        XCTAssertTrue(tail.contains("compactMap"))
    }
}
