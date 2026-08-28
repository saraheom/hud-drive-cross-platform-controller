import XCTest
@testable import HUDController

final class V90152AmbientDiagnosticFlightRecorderTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testFlightRecorderCapturesSimplifiedPerLightRuntimeState() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func ambientTrace(_ reason: String)"))
        XCTAssertTrue(monitor.contains("AMBIENT TRACE"))
        XCTAssertTrue(monitor.contains("engineDiag{hud="))
        XCTAssertTrue(monitor.contains("dayNight{raw="))
        XCTAssertTrue(monitor.contains("breath{sync="))
        XCTAssertFalse(monitor.contains("startup{complete="))
        XCTAssertFalse(monitor.contains("headlightPowerEpoch"))
        XCTAssertTrue(monitor.contains("ambientRoleTraceState(.door)"))
        XCTAssertTrue(monitor.contains("ambientRoleTraceState(.dashboard)"))
        XCTAssertTrue(monitor.contains("ambientRoleTraceState(.centerConsole)"))
    }

    func testDuplicateAdvertisementsCannotRestartSameConsensusWindow() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let block = monitor.components(separatedBy: "private func scheduleHeadlightConsensusEvaluation")[1]
            .components(separatedBy: "private func commitConfirmedHeadlightPower")[0]
        XCTAssertTrue(block.contains("if headlightConsensusCandidate == candidate"))
        XCTAssertTrue(block.contains("if headlightConsensusTask != nil { return }"))
        XCTAssertTrue(block.contains("AllowDuplicates enabled"))
        XCTAssertTrue(block.contains("SAME"))
    }

    func testEngineStartupClassifierIsRemovedAndDayNightRemainsThreeState() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertFalse(monitor.contains("private func startupHeadlightConsensus"))
        XCTAssertFalse(monitor.contains("private func finishVehicleStartupClassification"))
        XCTAssertFalse(monitor.contains("private func tryStartVehicleStartupBreath"))
        let block = monitor.components(separatedBy: "private func currentHeadlightConsensus")[1]
            .components(separatedBy: "private func scheduleHeadlightConsensusEvaluation")[0]
        XCTAssertTrue(block.contains("return .bothOn"))
        XCTAssertTrue(block.contains("return .bothOff"))
        XCTAssertTrue(block.contains("return .mixed"))
    }

    func testPerLightAnimationAndRestoreLifecycleIsExplicitlyLogged() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Fresh power-on boot settle scheduled"))
        XCTAssertTrue(monitor.contains("Fresh power-on boot settle complete"))
        XCTAssertTrue(monitor.contains("Breath prepare queued"))
        XCTAssertTrue(monitor.contains("Breath participant ready"))
        XCTAssertTrue(monitor.contains("Independent Breath begin"))
        XCTAssertTrue(monitor.contains("Synchronized Breath begin"))
        XCTAssertTrue(monitor.contains("Steady restore begin:"))
        XCTAssertTrue(monitor.contains("Steady restore complete:"))
        XCTAssertTrue(monitor.contains("One-shot fail-safe yielded without restore"))
    }

    func testOSMTraceLogsGPSPathCandidateGeometryAndFinalOutput() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("OSM TRACE GPS"))
        XCTAssertTrue(speed.contains("OSM TRACE PATH"))
        XCTAssertTrue(speed.contains("OSM TRACE MATCH"))
        XCTAssertTrue(speed.contains("OSM TRACE DECISION"))
        XCTAssertTrue(speed.contains("OSM TRACE OUTPUT"))
        XCTAssertTrue(speed.contains("seg=%.6f,%.6f>%.6f,%.6f"))
        XCTAssertTrue(speed.contains("speedTags=%@/%@/%@"))
    }

    func testV9010TransportBaselineRemainsUntouched() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(monitor.contains("private var bledimSequenceByID: [UUID: UInt8]"))
        XCTAssertFalse(monitor.contains("BLEDIM10Hz"))
        XCTAssertFalse(monitor.contains("scheduleRobustSteadyStateRecovery"))
    }
}
