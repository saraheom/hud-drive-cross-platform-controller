import XCTest
@testable import HUDController

final class V90VehicleAmbientAutomationTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testKnownVehicleRolesRemainConfigured() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("FBD8C9A0-"))
        XCTAssertTrue(monitor.contains("7A3B5F81-"))
        XCTAssertTrue(monitor.contains("51FA23D6-"))
        XCTAssertTrue(monitor.contains(".door"))
        XCTAssertTrue(monitor.contains(".dashboard"))
        XCTAssertTrue(monitor.contains(".centerConsole"))
    }

    func testDoorDayNightIsIndependentFromAnimation() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("steadyBrightnessTarget(for device"))
        XCTAssertTrue(monitor.contains("Center present → night Door brightness"))
        XCTAssertTrue(monitor.contains("Center absent → day Door brightness"))
        XCTAssertTrue(monitor.contains("automaticDoorDayNightTransitionSeconds: TimeInterval = 1.0"))
        XCTAssertTrue(monitor.contains("activeBreathReturnBrightness[doorID] = target"))
    }

    func testBothIndependentAndOptionalSynchronizedBreathPathsExist() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func startIndividualBreathSession"))
        XCTAssertTrue(monitor.contains("private func startSynchronizedBreathSession"))
        XCTAssertTrue(monitor.contains("let timelineTick = 0.05"))
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
    }

    func testOSMTraceFlightRecorderCanReplayMatcherDecision() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("OSM TRACE GPS"))
        XCTAssertTrue(speed.contains("OSM TRACE PATH"))
        XCTAssertTrue(speed.contains("OSM TRACE MATCH"))
        XCTAssertTrue(speed.contains("OSM TRACE DECISION"))
        XCTAssertTrue(speed.contains("currentDistance"))
        XCTAssertTrue(speed.contains("currentAngle"))
        XCTAssertTrue(speed.contains("matchedPoints"))
    }
}
