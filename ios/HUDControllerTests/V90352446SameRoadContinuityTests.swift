import Foundation
import XCTest
@testable import HUDController

final class V90352446SameRoadContinuityTests: XCTestCase {
    func testUntaggedMLKContinuesFromExplicit25MphTagForFiveMinutes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let street = CurrentNavRoadIdentity.normalizedRoadPhrase("Martin Luther King Jr Dr")
        var anchor = CurrentNavSameRoadContinuity.verified(
            identity: street, speedMph: 25, latitude: 39.98,
            longitude: -75.20, now: start)
        XCTAssertNotNil(anchor)
        for second in 1...300 {
            anchor = CurrentNavSameRoadContinuity.advance(
                anchor, roadIdentity: street,
                latitude: 39.98 + Double(second) * 0.0001,
                longitude: -75.20,
                now: start.addingTimeInterval(Double(second)),
                matchedSameRoadGeometry: true,
                contradictoryPostedLimitNearby: false)
            XCTAssertNotNil(anchor, "Expected a verified continuity match at second \(second)")
        }
        XCTAssertEqual(anchor?.speedMph, 25)
        XCTAssertEqual(anchor?.explicitlyVerifiedAt, start)
        XCTAssertGreaterThan(anchor?.travelledMeters ?? 0, 3_000)
    }

    func testDifferentStreetOrContradictoryPostedSpeedStopsCarry() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let road = CurrentNavRoadIdentity.normalizedRoadPhrase("MLK Dr")
        let anchor = CurrentNavSameRoadContinuity.verified(
            identity: road, speedMph: 25, latitude: 39.98,
            longitude: -75.20, now: start)
        XCTAssertNotNil(anchor)
        XCTAssertNil(CurrentNavSameRoadContinuity.advance(
            anchor, roadIdentity: "north 34th street",
            latitude: 39.9801, longitude: -75.20,
            now: start.addingTimeInterval(1),
            matchedSameRoadGeometry: true,
            contradictoryPostedLimitNearby: false))
        XCTAssertNil(CurrentNavSameRoadContinuity.advance(
            anchor, roadIdentity: road,
            latitude: 39.9801, longitude: -75.20,
            now: start.addingTimeInterval(1),
            matchedSameRoadGeometry: true,
            contradictoryPostedLimitNearby: true))
        XCTAssertNil(CurrentNavSameRoadContinuity.advance(
            anchor, roadIdentity: road,
            latitude: 39.9801, longitude: -75.20,
            now: start.addingTimeInterval(1),
            matchedSameRoadGeometry: false,
            contradictoryPostedLimitNearby: false))
        XCTAssertFalse(CurrentNavRoadIdentity.routeRoadMatches(
            "MLK Dr", name: "Schuylkill Expressway", reference: "I 76"))
    }

    func testCarryCannotExtendBeyondUnrefreshedAnchorLifetime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let anchor = CurrentNavSameRoadContinuity.verified(
            identity: "ridge avenue", speedMph: 25,
            latitude: 39.98, longitude: -75.20, now: start)
        XCTAssertNil(CurrentNavSameRoadContinuity.advance(
            anchor, roadIdentity: "ridge avenue", latitude: 39.9801,
            longitude: -75.20, now: start.addingTimeInterval(721),
            matchedSameRoadGeometry: true,
            contradictoryPostedLimitNearby: false))
    }
}
