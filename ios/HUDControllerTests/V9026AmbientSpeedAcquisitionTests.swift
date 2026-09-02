import XCTest
@testable import HUDController

final class V9026AmbientSpeedAcquisitionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testAutomaticBarrierWaitsForAdmittedBLEDIMPreparation() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("headlightSyncAdmittedPreparationHardCapSeconds: TimeInterval = 7.0"))
        XCTAssertTrue(monitor.contains("private func isAdmittedSyncMemberStillPreparing"))
        XCTAssertTrue(monitor.contains("Headlight sync barrier extending for admitted preparation"))
        XCTAssertTrue(monitor.contains("admittedPreparationHardDeadline"))
    }

    func testPersistentUnpoweredConnectRequestDoesNotCountAsPhysicalJoiner() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let physical = monitor.components(separatedBy: "private func isPhysicallyPresentOrConnecting")[1]
            .components(separatedBy: "private func isAdmittedSyncMemberStillPreparing")[0]
        XCTAssertFalse(physical.contains("connectionStartedByID[id] != nil"))
        XCTAssertTrue(physical.contains("peripheral.state == .connecting"))
        XCTAssertTrue(physical.contains("lastSeenByID[id]"))
        XCTAssertTrue(physical.contains("headlightRecentEvidenceSeconds"))
    }

    func testEngineStartupUsesPostCrankReacquisitionWindow() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("engineStartupHeadlightReacquireSeconds: TimeInterval = 15.0"))
        XCTAssertTrue(monitor.contains("engineStartupMaxWaitSeconds: TimeInterval = 16.0"))
        XCTAssertTrue(monitor.contains("post-crank reacquisition window"))
    }

    func testCurrentPhiladelphiaStreetCenterlineSchemaIsUsed() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("TRANSPORTATION_street_segment/FeatureServer/0/query"))
        XCTAssertTrue(speed.contains("POSTED_SPEED_LIMIT"))
        XCTAssertTrue(speed.contains("SPEED_LIMIT"))
        XCTAssertTrue(speed.contains("FULL_STREET_NAME"))
        XCTAssertTrue(speed.contains("layersOK=1/1"))
    }

    func testCompletedTurnAndCityCurrentGeometryFastAcquisitionArePresent() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("completed-turn road takeover"))
        XCTAssertTrue(speed.contains("currentCandidate!.match.currentAngle >= 45"))
        XCTAssertTrue(speed.contains("gisCurrentGeometryBest"))
        XCTAssertTrue(speed.contains("Philadelphia Street Centerline fast acquisition"))
        XCTAssertTrue(speed.contains("improvedSameRoadContinuityArmed = false"))
        XCTAssertTrue(speed.contains("currentLimitWarningEligible = false"))
    }

    func testRoadLevelConsensusRequiresAgreementAndIsDisplayOnly() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("private func sameRoadOSMSpeedConsensus"))
        XCTAssertTrue(speed.contains("observations.count >= 2"))
        XCTAssertTrue(speed.contains("values.count == 1"))
        XCTAssertTrue(speed.contains("OSM same-road corridor consensus"))
        XCTAssertTrue(speed.contains("warningEligible: false"))
    }
}
