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

    func testCriticalPowerColorAndFinalBrightnessAreRetriedInOrder() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func sendPowerWhenReady"))
        XCTAssertTrue(monitor.contains("private func sendColorWhenReady"))
        XCTAssertTrue(monitor.contains("private func applyRuntimeBrightnessWhenReady"))
        XCTAssertTrue(monitor.contains("power-up breath baseline"))
        XCTAssertTrue(monitor.contains("reason: \"power-up breath final\""))
    }

    func testDayNightConsensusDoesNotOwnAnimation() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("both Center + Dashboard stable ON"))
        XCTAssertTrue(monitor.contains("both Center + Dashboard stable OFF"))
        XCTAssertTrue(monitor.contains("Two-light day/night consensus"))
        XCTAssertTrue(monitor.contains("animation remains per-light power-on"))
    }
}
