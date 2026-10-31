import XCTest
@testable import HUDController

final class V90352433SpeedSwitchTests: XCTestCase {
    func testCardinalOmissionDoesNotConflateOppositeSignedStreets() {
        XCTAssertTrue(CurrentNavRoadIdentity.routeRoadMatches("N Mascher St", name: "Mascher Street", reference: nil))
        XCTAssertTrue(CurrentNavRoadIdentity.routeRoadMatches("Roosevelt Expy", name: "Roosevelt Expressway", reference: nil))
        XCTAssertTrue(CurrentNavRoadIdentity.routeRoadMatches("North 2nd Street", name: "2nd St", reference: nil))
        XCTAssertFalse(CurrentNavRoadIdentity.routeRoadMatches("N Mascher St", name: "S Mascher St", reference: nil))
        XCTAssertFalse(CurrentNavRoadIdentity.routeRoadMatches("Roosevelt Expy", name: "Roosevelt Boulevard", reference: nil))
    }

    func testAmbiguousParallelTaggedWaysRequireConfirmation() {
        XCTAssertTrue(CurrentNavSpeedSwitchPolicy.needsConfirmation(
            previousWayID: 1, proposedWayID: 2, previousKmh: 80, proposedKmh: 65,
            previousDistanceMeters: 8, proposedDistanceMeters: 7,
            previousHeadingErrorDegrees: 5, proposedHeadingErrorDegrees: 5))
        XCTAssertFalse(CurrentNavSpeedSwitchPolicy.needsConfirmation(
            previousWayID: 1, proposedWayID: 2, previousKmh: 80, proposedKmh: 65,
            previousDistanceMeters: 35, proposedDistanceMeters: 4,
            previousHeadingErrorDegrees: 5, proposedHeadingErrorDegrees: 5))
        XCTAssertFalse(CurrentNavSpeedSwitchPolicy.needsConfirmation(
            previousWayID: 1, proposedWayID: 2, previousKmh: 80, proposedKmh: 80,
            previousDistanceMeters: 7, proposedDistanceMeters: 6,
            previousHeadingErrorDegrees: 5, proposedHeadingErrorDegrees: 5))
    }
}
