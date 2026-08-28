import XCTest
@testable import HUDController

final class V90152AmbientDiagnosticFlightRecorderTests: XCTestCase {
    private func monitorSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift"),
            encoding: .utf8
        )
    }

    func testFlightRecorderCapturesConsensusAndPerLightState() throws {
        let monitor = try monitorSource()
        XCTAssertTrue(monitor.contains("private func ambientTrace(_ reason: String)"))
        XCTAssertTrue(monitor.contains("AMBIENT TRACE"))
        XCTAssertTrue(monitor.contains("engine{hud="))
        XCTAssertTrue(monitor.contains("startup{complete="))
        XCTAssertTrue(monitor.contains("headlight{raw="))
        XCTAssertTrue(monitor.contains("ambientRoleTraceState(.door)"))
        XCTAssertTrue(monitor.contains("ambientRoleTraceState(.dashboard)"))
        XCTAssertTrue(monitor.contains("ambientRoleTraceState(.centerConsole)"))
    }

    func testDuplicateAdvertisementsCannotRestartSameConsensusWindow() throws {
        let monitor = try monitorSource()
        let block = monitor.components(separatedBy: "private func scheduleHeadlightConsensusEvaluation")[1]
            .components(separatedBy: "private func commitConfirmedHeadlightPower")[0]
        XCTAssertTrue(block.contains("if headlightConsensusCandidate == candidate"))
        XCTAssertTrue(block.contains("if headlightConsensusTask != nil { return }"))
        XCTAssertTrue(block.contains("AllowDuplicates enabled"))
        XCTAssertTrue(block.contains("SAME"))
    }

    func testStartupMixedStateWaitsAndResolvedStateIsStableBeforeCommit() throws {
        let monitor = try monitorSource()
        XCTAssertTrue(monitor.contains("private func startupHeadlightConsensus"))
        let block = monitor.components(separatedBy: "private func finishVehicleStartupClassification()")[1]
            .components(separatedBy: "private func applyCurrentDoorDayNightTarget")[0]
        XCTAssertTrue(block.contains("if observation == .mixed"))
        XCTAssertTrue(block.contains("waiting for BOTH Dashboard + Center to agree"))
        XCTAssertTrue(block.contains("startupClassificationCandidate != observation"))
        XCTAssertTrue(block.contains("headlightConsensusStabilitySeconds"))
        XCTAssertTrue(block.contains("let night = observation == .bothOn"))
    }

    func testAnimationAndRestoreFailuresAreExplicitlyLogged() throws {
        let monitor = try monitorSource()
        XCTAssertTrue(monitor.contains("Vehicle-start Breath waiting"))
        XCTAssertTrue(monitor.contains("Consensus headlight Breath waiting"))
        XCTAssertTrue(monitor.contains("Breath prepare failed at Power ON"))
        XCTAssertTrue(monitor.contains("Breath prepare failed at RGB"))
        XCTAssertTrue(monitor.contains("Breath prepare failed at baseline brightness"))
        XCTAssertTrue(monitor.contains("Steady restore begin:"))
        XCTAssertTrue(monitor.contains("Steady restore complete:"))
        XCTAssertTrue(monitor.contains("One-shot fail-safe yielded without restore"))
    }

    func testV9010TransportBaselineRemainsUntouched() throws {
        let monitor = try monitorSource()
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(monitor.contains("private var bledimSequenceByID: [UUID: UInt8]"))
        XCTAssertFalse(monitor.contains("BLEDIM10Hz"))
        XCTAssertFalse(monitor.contains("scheduleRobustSteadyStateRecovery"))
    }
}
