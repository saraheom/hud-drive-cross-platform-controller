import XCTest
@testable import HUDController

final class V9016FieldHardeningTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBLEDIMBootSettlePrecedesOneCompletePowerOnSequence() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("bledimBootSettleDelaySeconds: TimeInterval = 1.50"))
        XCTAssertTrue(monitor.contains("Fresh power-on boot settle scheduled"))
        XCTAssertTrue(monitor.contains("starting one complete power-on sequence"))
        XCTAssertTrue(monitor.contains("self.queuePowerUpBreath(id)"))
    }

    func testAbortFailsafeStillProtectsTransientZeroBrightness() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Animation/fade aborted at transient level → restoring steady state"))
        XCTAssertTrue(monitor.contains("Task.sleep(for: .milliseconds(180))"))
        XCTAssertFalse(monitor.contains("confirmedHeadlightOff"))
    }

    func testOBDRetryBackoffRemainsBounded() throws {
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        XCTAssertTrue(obd.contains("case 1: retryDelay = 4.0"))
        XCTAssertTrue(obd.contains("default: retryDelay = 30.0"))
    }
}
