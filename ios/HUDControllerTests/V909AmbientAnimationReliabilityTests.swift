import XCTest
@testable import HUDController

final class V909AmbientAnimationReliabilityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBLEDIMAnimationPacingAndSequenceArePerPeripheral() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func sendBrightnessNormalized("))
        XCTAssertTrue(monitor.contains("let raw = UInt8((level * 255.0).rounded())"))
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(monitor.contains("private var bledimSequenceByID: [UUID: UInt8]"))
        XCTAssertTrue(monitor.contains("nextBLEDIMSequence(for id: UUID)"))
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
