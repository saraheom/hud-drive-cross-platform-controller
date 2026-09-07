import XCTest
@testable import HUDController

final class V9031CarPlayRouteGuidanceTests: XCTestCase {
    func testOriginalHudEtaPacketShape() {
        let arrival: Int64 = 1_788_441_853_000
        let packet = HudCommands.eta(arrivalTimeMilliseconds: arrival)
        let body = HudProtocol.unescape(packet)
        XCTAssertNotNil(body)
        XCTAssertEqual(body?.prefix(3), Data([2, 114, 0]))
        XCTAssertEqual(body?.dropFirst(3), HudProtocol.int64(arrival))
    }

    func testNavigationSourcePriority() {
        XCTAssertGreaterThan(
            RouteGuidanceAdapterClient.SourceKind.googleMaps.priority,
            RouteGuidanceAdapterClient.SourceKind.appleMaps.priority
        )
        XCTAssertGreaterThan(
            RouteGuidanceAdapterClient.SourceKind.appleMaps.priority,
            RouteGuidanceAdapterClient.SourceKind.waze.priority
        )
    }

    func testUnknownSourceNeverOutranksSupportedSources() {
        XCTAssertLessThan(
            RouteGuidanceAdapterClient.SourceKind.other.priority,
            RouteGuidanceAdapterClient.SourceKind.waze.priority
        )
    }

    func testSourceClassification() {
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Google Maps"), .googleMaps)
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Apple Maps"), .appleMaps)
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Maps"), .appleMaps)
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Waze"), .waze)
    }

    func testAppleMapsExplicitZeroDoesNotFallBackToStaleDestinationTableDistance() throws {
        let json = #"{"version":2,"sequence":266,"source":"Apple Maps","routeState":1,"active":true,"currentRoad":"Presidential Blvd","destination":"Target","estimatedArrivalUnixSeconds":1788809700,"timeRemainingSeconds":0,"distanceRemainingMeters":0,"distanceRemainingText":"0","distanceRemainingUnits":4,"distanceToManeuverMeters":0,"distanceToManeuverText":"0","distanceToManeuverUnits":2,"currentManeuverIndex":null,"nextManeuverIndex":12,"maneuverCount":15,"laneGuidanceShowing":false,"laneGuidanceIndex":0,"laneGuidance":null,"maneuvers":[{"index":12,"description":"","type":12,"afterRoad":"","distanceMeters":1931,"displayDistanceText":"1.2","drivingSide":0}]}"#
        let snapshot = try JSONDecoder().decode(
            RouteGuidanceAdapterClient.Snapshot.self,
            from: Data(json.utf8)
        )
        let maneuver = try XCTUnwrap(snapshot.maneuvers.first)

        XCTAssertEqual(
            RouteGuidanceAdapterClient.resolvedManeuverDistanceMeters(
                snapshot: snapshot,
                maneuver: maneuver
            ),
            0
        )
        XCTAssertEqual(
            RouteGuidanceAdapterClient.resolvedManeuverStreet(
                snapshot: snapshot,
                maneuver: maneuver,
                mapped: .destination
            ),
            "Target"
        )
    }

    func testAppleMapsArrivedStateForcesZeroEvenWhenDisplayDistanceTextIsMissing() throws {
        let json = #"{"version":2,"sequence":292,"source":"Apple Maps","routeState":2,"active":true,"currentRoad":"Presidential Blvd","destination":"Target","estimatedArrivalUnixSeconds":1788809820,"timeRemainingSeconds":0,"distanceRemainingMeters":0,"distanceRemainingText":"0","distanceRemainingUnits":4,"distanceToManeuverMeters":0,"distanceToManeuverText":"","distanceToManeuverUnits":2,"currentManeuverIndex":null,"nextManeuverIndex":12,"maneuverCount":15,"laneGuidanceShowing":false,"laneGuidanceIndex":0,"laneGuidance":null,"maneuvers":[{"index":12,"description":"","type":12,"afterRoad":"","distanceMeters":1931,"displayDistanceText":"1.2","drivingSide":0}]}"#
        let snapshot = try JSONDecoder().decode(
            RouteGuidanceAdapterClient.Snapshot.self,
            from: Data(json.utf8)
        )
        let maneuver = try XCTUnwrap(snapshot.maneuvers.first)

        XCTAssertEqual(
            RouteGuidanceAdapterClient.resolvedManeuverDistanceMeters(
                snapshot: snapshot,
                maneuver: maneuver
            ),
            0
        )
    }

    func testLegacyMissingLiveDistanceStillUsesManeuverTableFallback() throws {
        let json = #"{"version":1,"sequence":10,"source":"Apple Maps","routeState":1,"active":true,"currentRoad":"Ridge Ave","destination":"Target","estimatedArrivalUnixSeconds":0,"timeRemainingSeconds":300,"distanceRemainingMeters":2500,"distanceRemainingText":"","distanceRemainingUnits":0,"distanceToManeuverMeters":0,"distanceToManeuverText":"","distanceToManeuverUnits":0,"currentManeuverIndex":4,"nextManeuverIndex":null,"maneuverCount":1,"laneGuidanceShowing":false,"laneGuidanceIndex":null,"laneGuidance":null,"maneuvers":[{"index":4,"description":"Turn right","type":2,"afterRoad":"City Ave","distanceMeters":321,"displayDistanceText":"0.2","drivingSide":0}]}"#
        let snapshot = try JSONDecoder().decode(
            RouteGuidanceAdapterClient.Snapshot.self,
            from: Data(json.utf8)
        )
        let maneuver = try XCTUnwrap(snapshot.maneuvers.first)

        XCTAssertEqual(
            RouteGuidanceAdapterClient.resolvedManeuverDistanceMeters(
                snapshot: snapshot,
                maneuver: maneuver
            ),
            321
        )
    }

}
