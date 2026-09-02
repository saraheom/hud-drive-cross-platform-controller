import XCTest
@testable import HUDController

final class V9026AmbientSpeedAcquisitionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHeadlightCohortWaitsStrictlyForEveryEnrolledMember() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("headlightStrictReadyTimeoutSeconds: TimeInterval = 10.0"))
        XCTAssertTrue(monitor.contains("syncCohortExpectedIDs.isSubset(of: self.synchronizedBreathIDs)"))
        XCTAssertTrue(monitor.contains("HEADLIGHT STRICT-COHORT skipped"))
        XCTAssertTrue(monitor.contains("HEADLIGHT STRICT-COHORT common T0"))
    }

    func testCurrentPhiladelphiaStreetCenterlineSchemaAndDiagnosticsAreUsed() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("TRANSPORTATION_street_segment/FeatureServer/0/query"))
        XCTAssertTrue(speed.contains("POSTED_SPEED_LIMIT"))
        XCTAssertTrue(speed.contains("SPEED_LIMIT"))
        XCTAssertTrue(speed.contains("rawFeatures=%d"))
        XCTAssertTrue(speed.contains("featuresWithSpeed=%d"))
        XCTAssertTrue(speed.contains("featuresWithGeometry=%d"))
        XCTAssertTrue(speed.contains("parsedSegments=%d"))
    }

    func testCompletedTurnAndRoadConsensusRemain() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("completed-turn road takeover"))
        XCTAssertTrue(speed.contains("gisCurrentGeometryBest"))
        XCTAssertTrue(speed.contains("OSM same-road corridor consensus"))
        XCTAssertTrue(speed.contains("warningEligible: false"))
    }
}
