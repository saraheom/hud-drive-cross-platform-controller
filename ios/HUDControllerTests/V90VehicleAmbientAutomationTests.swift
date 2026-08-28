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

    func testEngineOffSuppressesAutomaticBreathWithoutShutdownFade() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Engine power OFF confirmed by HUD + OBD2 absence"))
        XCTAssertTrue(monitor.contains("automatic Breath is suppressed"))
        XCTAssertTrue(monitor.contains("vehicleStartupAnimationPending = false"))
        XCTAssertFalse(monitor.contains("performVehicleShutdownFade(trigger: \"engine power OFF\")"))
        XCTAssertFalse(monitor.contains("vehicleShutdownLatched"))
    }

    func testDoorDayNightStateMachineIsSimplified() throws {
        let source = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(source.contains("beginVehicleStartupClassification"))
        XCTAssertTrue(source.contains("finishVehicleStartupClassification"))
        XCTAssertTrue(source.contains("startupHeadlightPowerPresent()"))
        XCTAssertTrue(source.contains("applyCurrentDoorDayNightTarget"))
        XCTAssertFalse(source.contains("fadeInNewHeadlightDevices"))
        XCTAssertFalse(source.contains("vehicleJoinedHeadlightIDs"))
    }

    func testSmoothBrightnessAndSynchronizedBreathExist() throws {
        let source = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(source.contains("private func transitionBrightness("))
        XCTAssertTrue(source.contains("let timelineTick = 0.05"))
        XCTAssertTrue(source.contains("private func sendBrightnessNormalized("))
        XCTAssertTrue(source.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(source.contains("private func startSynchronizedBreathSession()"))
        XCTAssertTrue(source.contains("from = Double(clampedStart); to = 0"))
        XCTAssertTrue(source.contains("from = 0; to = 100"))
        // v90.8.1: every repetition returns to the captured initial brightness,
        // except the last return leg may land on a target changed while the breath
        // is running. Keep CI aligned with the runtime implementation rather than
        // the older v90.8 fixed-return source string.
        XCTAssertTrue(source.contains("to = Double(cycleIndex == safeCycles - 1 ? clampedReturn : clampedStart)"))
        XCTAssertTrue(source.contains("let perCycleDuration = max(1.0, min(15.0, breathDurationSeconds))"))
        XCTAssertTrue(source.contains("let totalDuration = perCycleDuration * Double(cycles)"))
    }

    func testEnginePowerUsesHUDAndOBDWitness() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let appState = try source("HUDController/App/AppState.swift")
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")

        XCTAssertTrue(monitor.contains("func hudTransportPowerSignal(_ present: Bool)"))
        XCTAssertTrue(monitor.contains("func obdPowerSignal(_ present: Bool)"))
        XCTAssertTrue(monitor.contains("private enum EnginePowerConsensusObservation"))
        XCTAssertTrue(monitor.contains("stable HUD + OBD2 consensus"))
        XCTAssertTrue(monitor.contains("scheduleEnginePowerOffConfirmation"))
        XCTAssertTrue(monitor.contains("directOBDWitnessProven"))
        XCTAssertTrue(appState.contains("self.ambientLight.hudTransportPowerSignal(true)"))
        XCTAssertTrue(appState.contains("self.ambientLight.hudTransportPowerSignal(false)"))
        XCTAssertTrue(appState.contains("!self.bluetooth.userDisconnectRequested"))
        XCTAssertTrue(obd.contains("var onConnectionChanged: ((Bool) -> Void)?"))
        XCTAssertTrue(obd.contains("onConnectionChanged?(false)"))
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
