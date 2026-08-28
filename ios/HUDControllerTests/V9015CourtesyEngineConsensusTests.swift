import XCTest
@testable import HUDController

final class V9015CourtesyEngineConsensusTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testEngineOnRequiresHUDAndOBDConsensus() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private enum EnginePowerConsensusObservation"))
        XCTAssertTrue(monitor.contains("if hudEnginePowerSignalPresent && obdEnginePowerSignalPresent { return .bothOn }"))
        XCTAssertTrue(monitor.contains("if !hudEnginePowerSignalPresent && !obdEnginePowerSignalPresent { return .bothOff }"))
        XCTAssertTrue(monitor.contains("engineSignalConsensusStabilitySeconds: TimeInterval = 0.75"))
        XCTAssertTrue(monitor.contains("directOBDAcquireWindowSeconds: TimeInterval = 5.0"))
        XCTAssertTrue(monitor.contains("stable HUD + OBD2 consensus"))
        XCTAssertTrue(monitor.contains("Engine consensus mixed; preserving confirmed"))
    }

    func testDirectOBDIsOnlyAnOffVeto() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let witness = monitor.components(separatedBy: "private func recordIndependentOBDWitness")[1]
            .components(separatedBy: "private func isDirectOBDRecentlyPresent")[0]
        XCTAssertFalse(witness.contains("confirmEnginePowerOn"))
        XCTAssertTrue(witness.contains("engineOffConfirmationTask?.cancel()"))
        XCTAssertTrue(monitor.contains("independent OBD witness vetoes engine OFF"))
    }

    func testHUDLossPublishesOBDDisconnectedState() throws {
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        let block = obd.components(separatedBy: "func transportDisconnected()")[1]
            .components(separatedBy: "private func startAutoConnectLoop")[0]
        XCTAssertTrue(block.contains("connected = false"))
        XCTAssertTrue(block.contains("onConnectionChanged?(false)"))
        XCTAssertTrue(block.contains("physical OBD power remains independently witnessable"))
    }

    func testCourtesyLightsCannotConsumeAutomaticStartupBreath() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("v90.15 courtesy gate"))
        XCTAssertTrue(monitor.contains("!enginePowerPresent || !vehicleStartupCompleted || vehicleStartupAnimationPending"))
        XCTAssertTrue(monitor.contains("Headlight consensus deferred during courtesy/startup gate"))
        XCTAssertTrue(monitor.contains("private func tryStartVehicleStartupBreath"))
    }

    func testNightStartupWaitsForAllThreeControllers() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let block = monitor.components(separatedBy: "private func tryStartVehicleStartupBreath")[1]
            .components(separatedBy: "/// Record positive physical-power evidence")[0]
        XCTAssertTrue(block.contains("let doorID = deviceID(for: .door)"))
        XCTAssertTrue(block.contains("if vehicleHeadlightsActive"))
        XCTAssertTrue(block.contains("isControllable(dashboardID)"))
        XCTAssertTrue(block.contains("isControllable(centerID)"))
        XCTAssertTrue(block.contains("Vehicle-start Breath admitted mode="))
    }

    func testStartupClassifierDoesNotStartCompetingDoorFade() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let block = monitor.components(separatedBy: "private func finishVehicleStartupClassification()")[1]
            .components(separatedBy: "private func applyCurrentDoorDayNightTarget")[0]
        XCTAssertTrue(block.contains("tryStartVehicleStartupBreath"))
        XCTAssertFalse(block.contains("applyCurrentDoorDayNightTarget("))
        XCTAssertTrue(block.contains("Do not begin a separate Door fade here"))
    }
}
