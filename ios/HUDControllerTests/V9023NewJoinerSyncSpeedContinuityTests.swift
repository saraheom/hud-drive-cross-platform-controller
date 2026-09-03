import XCTest
@testable import HUDController

final class V9023NewJoinerSyncSpeedContinuityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testProductionBLEDIMIsAlreadyOnMinimalAndLabUIIsRemoved() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(monitor.contains("? .alreadyOnMinimal"))
        XCTAssertTrue(monitor.contains("case .alreadyOnMinimal:"))
        XCTAssertFalse(view.contains("BLEDIM ANIMATION TEST LAB"))
        XCTAssertTrue(view.contains("BLEDIM PRODUCTION ANIMATION"))
    }

    func testLaterHeadlightBarrierIsStrictNewJoinerCohort() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("let joiningDevices = pairedDevices.filter { automaticHeadlightJoinEligible($0) }"))
        XCTAssertTrue(monitor.contains("Door is enrolled only when Door itself is newly joining"))
        XCTAssertTrue(monitor.contains("joiningRoles.contains(.centerConsole) || joiningRoles.contains(.dashboard)"))
        XCTAssertTrue(monitor.contains("HEADLIGHT STRICT-COHORT common T0"))
        XCTAssertTrue(monitor.contains("no partial/late Breath"))
    }

    func testUpgradeSyncMigrationAndSpeedContinuityRemain() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(monitor.contains("HUD.Ambient.v90_22.headlightBarrierSyncMigrated"))
        XCTAssertTrue(monitor.contains("Flight recorder v90.29 enabled"))
        XCTAssertTrue(monitor.contains("startupSync=HUD-gated-all-three"))
        XCTAssertTrue(monitor.contains("headlightSync=new-joiners-strict"))
        XCTAssertTrue(speed.contains("private static func normalizedRoadIdentity"))
        XCTAssertTrue(speed.contains("same-road fast handoff"))
        XCTAssertTrue(speed.contains("same-road untagged continuity"))
    }
}
