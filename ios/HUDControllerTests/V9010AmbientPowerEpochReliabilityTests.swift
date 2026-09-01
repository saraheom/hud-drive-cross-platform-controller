import XCTest
@testable import HUDController

final class V9010AmbientPowerEpochReliabilityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV9010BLEDIMTransportBaselineRemains() throws {
        let model = try source("HUDController/Vehicle/AmbientLightModels.swift")
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(model.contains("static func brightnessRaw(_ value: UInt8"))
        XCTAssertTrue(monitor.contains("let raw = UInt8((level * 255.0).rounded())"))
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(monitor.contains("private var bledimSequenceByID: [UUID: UInt8]"))
        XCTAssertFalse(monitor.contains("BLEDIM10Hz"))
    }

    func testCriticalRestoreWritesRemainAndProductionBLEDIMUsesMinimal() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func sendPowerWhenReady"))
        XCTAssertTrue(monitor.contains("private func sendColorWhenReady"))
        XCTAssertTrue(monitor.contains("private func applyRuntimeBrightnessWhenReady"))
        XCTAssertTrue(monitor.contains("power-up breath terminal Power ON"))
        XCTAssertTrue(monitor.contains("power-up breath terminal RGB"))
        XCTAssertTrue(monitor.contains("? .alreadyOnMinimal"))
        XCTAssertTrue(monitor.contains("case .v90172Baseline, .baselineHold, .brightnessOnlyFinish, .noTerminalCommit:"))
        XCTAssertTrue(monitor.contains("power-up breath terminal Power ON"))
    }

    func testCenterOwnsFastDayNightAndTwoLightCrosscheckDoesNotOwnAnimation() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Fast Center day/night"))
        XCTAssertTrue(monitor.contains("Dashboard+Center diagnostic consensus"))
        XCTAssertTrue(monitor.contains("Center/BLEDOM remains authoritative for fast day/night"))

        let startupParts = monitor.components(separatedBy: "private func runStartupAnimationIfNeeded")
        XCTAssertGreaterThan(startupParts.count, 1)
        let startupBlock = startupParts[1].components(separatedBy: "private func queuePowerUpBreath")[0]
        XCTAssertTrue(startupBlock.contains("registerPowerOnCohortMember(id)"))
        XCTAssertTrue(startupBlock.contains("scheduleBLEDIMBootSettleReassert"))
        // v90.24+ recomputes barrier ownership after registerPowerOnCohortMember()
        // because that call may admit a just-arrived physical peer during the discovery floor.
        // Verify the new semantics rather than the pre-v90.24 one-line call shape.
        XCTAssertTrue(startupBlock.contains("let ownedByHeadlightBarrierNow = syncHeadlightBarrierActive && syncCohortExpectedIDs.contains(id)"))
        XCTAssertTrue(startupBlock.contains("force: ownedByHeadlightBarrierNow || lateFromHeadlightBarrier"))
        XCTAssertTrue(startupBlock.contains("deferVisualPreparationForSync: ownedByHeadlightBarrierNow"))
        XCTAssertFalse(startupBlock.contains("enginePowerPresent"))
        XCTAssertFalse(startupBlock.contains("headlightPowerSessionActive"))
    }
}
