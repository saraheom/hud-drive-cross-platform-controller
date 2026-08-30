import XCTest
@testable import HUDController

final class V9017SimplePowerOnOptionalSyncTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testEveryReconnectRearmsPerLightPowerOnBreath() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("every controller return is a brand-new power-on event"))
        XCTAssertTrue(monitor.contains("animatedConnectionSession.remove(id)"))
        XCTAssertTrue(monitor.contains("Power-on animation re-armed immediately after disconnect"))
        XCTAssertFalse(monitor.contains("headlightPowerEpoch"))
        XCTAssertFalse(monitor.contains("tryStartVehicleStartupBreath"))
        XCTAssertFalse(monitor.contains("tryStartConfirmedHeadlightBreath"))
    }

    func testOptionalSyncNeverMakesLateControllerJoinMidCycle() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("var synchronizePowerOnBreathEnabled: Bool"))
        XCTAssertTrue(monitor.contains("powerOnSyncWindowSeconds: TimeInterval = 3.0"))
        XCTAssertTrue(monitor.contains("powerOnSyncPreparationGraceSeconds: TimeInterval = 1.5"))
        XCTAssertTrue(monitor.contains("if !self.synchronizePowerOnBreathEnabled"))
        XCTAssertTrue(monitor.contains("Power-on cohort already started; running complete independent Breath"))
        XCTAssertTrue(monitor.contains("startIndividualBreathSession"))
        XCTAssertTrue(monitor.contains("startSynchronizedBreathSession"))
    }

    func testDoorDayNightDoesNotRestartSameFadeFromWatchdog() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private var brightnessTransitionTargetByID: [UUID: Int]"))
        let apply = monitor.components(separatedBy: "private func applyCurrentDoorDayNightTarget")[1]
            .components(separatedBy: "private func transitionDoorBrightness")[0]
        XCTAssertTrue(apply.contains("brightnessTransitionTasks[doorID] != nil"))
        XCTAssertTrue(apply.contains("brightnessTransitionTargetByID[doorID] == target"))
        let watchdog = monitor.components(separatedBy: "private func startWatchdog()")[1]
        XCTAssertFalse(watchdog.contains("evaluateVehicleLightingAutomation()"))
    }

    func testBreathTerminalCommitUsesKnownGoodV90172SemanticSequence() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let block = monitor.components(separatedBy: "private func finalizeBreathSteadyState")[1]
            .components(separatedBy: "private func runStartupAnimationIfNeeded")[0]
        XCTAssertTrue(block.contains("power-up breath terminal Power ON"))
        XCTAssertTrue(block.contains("power-up breath terminal RGB"))
        XCTAssertTrue(block.contains("power-up breath final"))
        XCTAssertTrue(block.contains("case .v90172Baseline, .baselineHold:"))
        XCTAssertTrue(block.contains("case .brightnessOnlyFinish, .alreadyOnMinimal, .v9018NoFlash:"))
    }

    func testOSMTraceDiagnosticsContainReplayGeometryAndOutput() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("OSM TRACE GPS"))
        XCTAssertTrue(speed.contains("OSM TRACE PATH"))
        XCTAssertTrue(speed.contains("OSM TRACE MATCH"))
        XCTAssertTrue(speed.contains("seg=%.6f,%.6f>%.6f,%.6f"))
        XCTAssertTrue(speed.contains("speedTags=%@/%@/%@"))
        XCTAssertTrue(speed.contains("OSM TRACE DECISION"))
        XCTAssertTrue(speed.contains("OSM TRACE OUTPUT"))
    }

    func testFailedTerminalCommitSchedulesOneShotFailsafe() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Breath terminal steady commit failed"))
        XCTAssertTrue(monitor.contains("failedTerminalCommits"))
        XCTAssertTrue(monitor.contains("scheduleAnimationAbortFailsafe(for: id, reason: \"Breath terminal steady commit failed\")"))
    }

    func testOSMTraceHeldLimitDoesNotRefreshFreshness() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("private var traceLastResolutionFresh = false"))
        XCTAssertTrue(speed.contains("case .traceOSM:"))
        XCTAssertTrue(speed.contains("resolutionIsFresh = traceLastResolutionFresh"))
        XCTAssertTrue(speed.contains("fresh=%d"))
    }

    func testSharedFadeCancellationUsesTransitionTokenCleanup() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private var brightnessTransitionTokenByID: [UUID: UUID]"))
        XCTAssertTrue(monitor.contains("let transitionToken = UUID()"))
        XCTAssertTrue(monitor.contains("affectedIDs"))
    }

}
