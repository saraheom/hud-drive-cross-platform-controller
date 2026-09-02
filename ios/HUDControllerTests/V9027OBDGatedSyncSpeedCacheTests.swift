import XCTest
@testable import HUDController

final class V9027OBDGatedSyncSpeedCacheTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testAutomaticBreathIsOBDGatedAndHUDDoesNotArmIt() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Automatic Breath held until OBD connection"))
        XCTAssertTrue(monitor.contains("scheduleEngineStartupSynchronization(source: \"OBD connected\")"))
        XCTAssertTrue(monitor.contains("HUD transport remains available for engine diagnostics"))
        XCTAssertTrue(monitor.contains("it no longer arms ambient animation"))
    }

    func testOBDStartupRequiresExactlyCenterDoorDashboard() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("requiredRoles: Set<AmbientLightRole> = [.centerConsole, .door, .dashboard]"))
        XCTAssertTrue(monitor.contains("OBD STARTUP FULL-COHORT common T0 ready=3 late=0"))
        XCTAssertTrue(monitor.contains("strict all-three readiness not met"))
        XCTAssertTrue(monitor.contains("no partial/late Breath"))
    }

    func testLaterHeadlightPairsCenterDashboardWithoutReplayingActiveDoor() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("for role in [AmbientLightRole.centerConsole, AmbientLightRole.dashboard]"))
        XCTAssertTrue(monitor.contains("Door is enrolled only when Door itself is newly joining"))
        XCTAssertTrue(monitor.contains("HEADLIGHT STRICT-COHORT common T0"))
    }

    func testSpeedCacheIsBoundedAndDisplayOnly() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("improvedRoadLimitCacheMaxAgeSeconds: TimeInterval = 90.0"))
        XCTAssertTrue(speed.contains("improvedRoadLimitCacheMaxDistanceMeters: CLLocationDistance = 1_200"))
        XCTAssertTrue(speed.contains("improvedRoadLimitCacheMaxCourseDeltaDegrees: Double = 35.0"))
        XCTAssertTrue(speed.contains("cached same-road limit hold"))
        XCTAssertTrue(speed.contains("Cached same-road display hold — disable native warning threshold"))
    }

    func testPhiladelphiaDiagnosticsExposePipelineCounts() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("rawFeatures=%d"))
        XCTAssertTrue(speed.contains("featuresWithSpeed=%d"))
        XCTAssertTrue(speed.contains("featuresWithGeometry=%d"))
        XCTAssertTrue(speed.contains("parsedSegments=%d"))
    }
}
