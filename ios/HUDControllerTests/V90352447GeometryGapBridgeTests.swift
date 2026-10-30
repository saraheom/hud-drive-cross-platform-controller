import Foundation
import XCTest
@testable import HUDController

final class V90352447GeometryGapBridgeTests: XCTestCase {
    func testMLKDriveSignIsRetainedDuringShortOfflineTileSeam() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let road = CurrentNavRoadIdentity.normalizedRoadPhrase("Martin Luther King Jr Dr")
        let anchor = CurrentNavSameRoadContinuity.verified(
            identity: road, speedMph: 25, latitude: 39.984,
            longitude: -75.2, now: start)
        XCTAssertNotNil(anchor)
        for second in 1...16 {
            let result = CurrentNavSameRoadContinuity.bridgeUnmappedGap(
                anchor, roadIdentity: road,
                latitude: 39.984 + Double(second) * 0.00017,
                longitude: -75.2, now: start.addingTimeInterval(Double(second)),
                freshNavigationStreet: true, routeTransition: false,
                differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false)
            XCTAssertEqual(result?.speedMph, 25)
            XCTAssertEqual(result?.lastConfirmedAt, start)
        }
        XCTAssertNil(CurrentNavSameRoadContinuity.bridgeUnmappedGap(
            anchor, roadIdentity: road, latitude: 39.9841,
            longitude: -75.2, now: start.addingTimeInterval(31),
            freshNavigationStreet: true, routeTransition: false,
            differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false))
    }

    func testConflictingLimitStreetChangeAndStaleNavigationStopTheBridge() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let anchor = CurrentNavSameRoadContinuity.verified(
            identity: "martin luther king drive", speedMph: 25,
            latitude: 39.984, longitude: -75.2, now: start)
        let now = start.addingTimeInterval(4)
        XCTAssertNil(CurrentNavSameRoadContinuity.bridgeUnmappedGap(
            anchor, roadIdentity: "falls road", latitude: 39.9841,
            longitude: -75.2, now: now, freshNavigationStreet: true,
            routeTransition: false, differentRoadGeometryNearby: false,
            contradictoryPostedLimitNearby: false))
        XCTAssertNil(CurrentNavSameRoadContinuity.bridgeUnmappedGap(
            anchor, roadIdentity: "martin luther king drive", latitude: 39.9841,
            longitude: -75.2, now: now, freshNavigationStreet: false,
            routeTransition: false, differentRoadGeometryNearby: false,
            contradictoryPostedLimitNearby: false))
        XCTAssertNil(CurrentNavSameRoadContinuity.bridgeUnmappedGap(
            anchor, roadIdentity: "martin luther king drive", latitude: 39.9841,
            longitude: -75.2, now: now, freshNavigationStreet: true,
            routeTransition: false, differentRoadGeometryNearby: true,
            contradictoryPostedLimitNearby: false))
        XCTAssertNil(CurrentNavSameRoadContinuity.bridgeUnmappedGap(
            anchor, roadIdentity: "martin luther king drive", latitude: 39.9841,
            longitude: -75.2, now: now, freshNavigationStreet: true,
            routeTransition: false, differentRoadGeometryNearby: false,
            contradictoryPostedLimitNearby: true))
    }
}
