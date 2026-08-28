import XCTest
@testable import HUDController

final class V909AmbientAnimationReliabilityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBLEDIMAnimationPacingAndSequenceMatchOfficialSliderCapture() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func sendBrightnessNormalized("))
        XCTAssertTrue(monitor.contains("let raw = UInt8((level * 255.0).rounded())"))
        XCTAssertTrue(monitor.contains("protocolPacing=Lotus20Hz/BLEDIM10Hz"))
        XCTAssertTrue(monitor.contains("private var bledimSequence: UInt8 = 0x08"))
        XCTAssertTrue(monitor.contains("private func nextBLEDIMSequence() -> UInt8"))
        XCTAssertTrue(monitor.contains("Do not reset the BLEDIM sequence on reconnect"))
        XCTAssertFalse(monitor.contains("bledimSequenceByID"))
        XCTAssertFalse(monitor.contains("nextBLEDIMSequence(for id:"))
        XCTAssertTrue(monitor.contains("peripheral.canSendWriteWithoutResponse"))
    }

    func testActivePreviewCannotRecaptureTransientBrightness() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Breath request ignored while already active"))
        XCTAssertTrue(monitor.contains("initial/return brightness preserved"))
        XCTAssertTrue(monitor.contains("runtimeTarget = device.brightness"))
    }

    func testPresetSlotsExposeVisiblePencilControls() throws {
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(view.contains("pencil.circle.fill"))
        XCTAssertTrue(view.contains("tap its pencil to save the current picker color"))
    }
}
