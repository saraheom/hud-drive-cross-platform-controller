import XCTest
@testable import HUDController

final class V9025SpeedContinuityRefinementTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testSuccessorHandoffAndPendingSameLimitContinuityArePresent() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("v90.25 forward-successor escape hatch"))
        XCTAssertTrue(speed.contains("item.match.currentDistance <= 20"))
        XCTAssertTrue(speed.contains("item.match.currentAngle <= 20"))
        XCTAssertTrue(speed.contains("same-road successor untagged continuity"))
        XCTAssertTrue(speed.contains("OSM pending same-limit road confirmation"))
        XCTAssertTrue(speed.contains("suppress stale display clear without refreshing warning freshness"))
    }

    func testContinuityDoesNotBecomeWarningFreshness() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("!improvedDisplayContinuityFresh"))
        XCTAssertTrue(speed.contains("warning freshness unchanged"))
        XCTAssertTrue(speed.contains("private var improvedDisplayContinuityReason = \"none\""))
    }

    func testIntegratedBuildKeepsV9024AmbientCoordinator() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Flight recorder v90.26 enabled"))
        XCTAssertTrue(monitor.contains("syncMembership=newJoinersOnly"))
        XCTAssertTrue(monitor.contains("autoSyncPrep=deferredToT0"))
        XCTAssertTrue(monitor.contains("engineStartupPromotion=fullCohort"))
    }
}
