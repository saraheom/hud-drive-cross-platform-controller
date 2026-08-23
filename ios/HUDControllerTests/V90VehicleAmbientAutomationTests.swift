import XCTest
@testable import HUDController

final class V90VehicleAmbientAutomationTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testKnownVehicleRolesAreMigrated() throws {
        let source = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(source.contains("FBD8C9A0-"))
        XCTAssertTrue(source.contains("7A3B5F81-"))
        XCTAssertTrue(source.contains("51FA23D6-"))
        XCTAssertTrue(source.contains(".door"))
        XCTAssertTrue(source.contains(".dashboard"))
        XCTAssertTrue(source.contains(".centerConsole"))
    }

    func testShutdownPreservesPreferredBrightness() throws {
        let model = try source("HUDController/Vehicle/AmbientLightModels.swift")
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(model.contains("var lastAppliedBrightness: Int?"))
        XCTAssertTrue(model.contains("var brightness: Int"))
        XCTAssertTrue(monitor.contains("applyRuntimeBrightness(id, percent: 0, reason: \"vehicle shutdown final\", persist: true)"))
        XCTAssertTrue(monitor.contains("preferred brightness preserved"))
        XCTAssertFalse(monitor.contains("$0.brightness = 0"))
    }

    func testDayNightAndHeadlightJoinStateMachineExists() throws {
        let source = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(source.contains("beginVehicleStartupClassification"))
        XCTAssertTrue(source.contains("finishVehicleStartupClassification"))
        XCTAssertTrue(source.contains("Night startup classified"))
        XCTAssertTrue(source.contains("Day startup classified"))
        XCTAssertTrue(source.contains("Headlight OFF→ON"))
        XCTAssertTrue(source.contains("fadeInNewHeadlightDevices"))
    }


    func testLateHeadlightGATTReadinessRemainsEligibleForJoinFade() throws {
        let source = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(source.contains("vehicleJoinedHeadlightIDs.formUnion(ids.filter"))
        XCTAssertTrue(source.contains("pairedDevice($0)?.role?.isHeadlightFed == true"))
        XCTAssertFalse(source.contains("vehicleJoinedHeadlightIDs.formUnion(roleIDs([.dashboard, .centerConsole]).filter { isLogicallyPowered($0) })"))
    }

    func testEnginePowerUsesHUDAndOBDSignalsWithDebouncedAutomaticShutdown() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let appState = try source("HUDController/App/AppState.swift")
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")

        XCTAssertTrue(monitor.contains("func hudTransportPowerSignal(_ present: Bool)"))
        XCTAssertTrue(monitor.contains("func obdPowerSignal(_ present: Bool)"))
        XCTAssertTrue(monitor.contains("scheduleEnginePowerOffConfirmation"))
        XCTAssertTrue(monitor.contains("directOBDWitnessProven"))
        XCTAssertTrue(monitor.contains("performVehicleShutdownFade(trigger: \"engine power OFF\")"))
        XCTAssertTrue(appState.contains("self.ambientLight.hudTransportPowerSignal(true)"))
        XCTAssertTrue(appState.contains("self.ambientLight.hudTransportPowerSignal(false)"))
        XCTAssertTrue(appState.contains("!self.bluetooth.userDisconnectRequested"))
        XCTAssertTrue(obd.contains("var onConnectionChanged: ((Bool) -> Void)?"))
        XCTAssertTrue(obd.contains("self.onConnectionChanged?(connected)"))
        XCTAssertFalse(monitor.contains("engineRPM >"))
    }

    func testStockSpeedWarningSemanticsRemainUntouched() throws {
        let source = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(source.contains("HudCommands.speedWarningThreshold(legalLimitMph)"))
        XCTAssertTrue(source.contains("SPEED_ALERTS_METHOD=0"))
        XCTAssertTrue(source.contains("SPEED_TOLERANCE_VALUE=0"))
        XCTAssertFalse(source.contains("legalLimitMph +"))
    }
}
