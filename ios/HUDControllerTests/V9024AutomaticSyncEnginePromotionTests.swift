import XCTest
@testable import HUDController

final class V9024AutomaticSyncEnginePromotionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testCourtesyBarrierUsesPhysicalNewJoinersOnly() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func isPhysicallyPresentOrConnecting"))
        XCTAssertTrue(monitor.contains("private func automaticHeadlightJoinEligible"))
        XCTAssertTrue(monitor.contains("let joiningDevices = pairedDevices.filter { automaticHeadlightJoinEligible($0) }"))
        XCTAssertTrue(monitor.contains("headlightSyncDiscoveryFloorSeconds: TimeInterval = 2.0"))
        XCTAssertTrue(monitor.contains("Headlight sync barrier opened NEW-JOINERS-ONLY physicalExpected="))
    }

    func testAutomaticLotusPreparationIsReadinessOnlyUntilCommonT0() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("deferVisualPreparationForSync: Bool = false"))
        XCTAssertTrue(monitor.contains("Lotus automatic sync preparation readiness-only; no pre-T0 Power/RGB/brightness write"))
        XCTAssertTrue(monitor.contains("deferVisualPreparationForSync: ownedByHeadlightBarrierNow"))
    }

    func testRawEngineWitnessDefersProvisionalAutomaticBreaths() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("engineStartupSyncCandidateActive || engineStartupSyncPending"))
        XCTAssertTrue(monitor.contains("Automatic Breath deferred to engine-start coordinator"))
        XCTAssertTrue(monitor.contains("Headlight sync barrier deferred to engine-start coordinator"))
        XCTAssertTrue(monitor.contains("supersedePendingHeadlightBarrierForEngineStartup(reason: \"raw HUD engine ON\")"))
    }

    func testConfirmedEngineStartPromotesFullThreeRoleCohortAfterCrankSettle() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("engineStartupCrankSettleSeconds: TimeInterval = 4.0"))
        XCTAssertTrue(monitor.contains("engineStartupBLEDIMQuietSeconds: TimeInterval = 1.5"))
        XCTAssertTrue(monitor.contains("engineStartupMaxWaitSeconds: TimeInterval = 9.0"))
        XCTAssertTrue(monitor.contains("private func scheduleEngineStartupSynchronization"))
        XCTAssertTrue(monitor.contains("private func beginEngineStartupFullSyncCohort"))
        XCTAssertTrue(monitor.contains("ENGINE-START FULL-COHORT opened"))
        XCTAssertTrue(monitor.contains("ENGINE-START FULL-COHORT common T0"))
        XCTAssertTrue(monitor.contains("deferVisualPreparationForSync: true"))
    }

    func testEngineOffRearmsOneTimeStartupPromotion() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("engineStartupSyncCompletedForCurrentEngineSession = false"))
        XCTAssertTrue(monitor.contains("re-arms the one-time engine-start synchronization promotion"))
    }

    func testUIExplainsStartupExceptionAndLaterNewJoinersOnlyRule() throws {
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(view.contains("only lights newly joining the current startup/headlight transition"))
        XCTAssertTrue(view.contains("A light that is already active stays untouched"))
        XCTAssertTrue(view.contains("initial confirmed engine start is the one deliberate exception"))
        XCTAssertTrue(view.contains("even if Dashboard was already on from courtesy lighting"))
    }
}
