import XCTest
@testable import HUDController

final class V9010AmbientPowerEpochReliabilityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBLEDIMUsesRawBrightnessOnSharedTwentyHertzTimeline() throws {
        let model = try source("HUDController/Vehicle/AmbientLightModels.swift")
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(model.contains("static func brightnessRaw(_ value: UInt8"))
        XCTAssertTrue(monitor.contains("private func sendBrightnessNormalized("))
        XCTAssertTrue(monitor.contains("let raw = UInt8((level * 255.0).rounded())"))
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertTrue(monitor.contains("0.05"))
        XCTAssertFalse(monitor.contains("protocolPacing=BLEDIM10Hz/Lotus20Hz"))
    }

    func testCriticalWritesAreSerializedAndRetried() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func sendPowerWhenReady"))
        XCTAssertTrue(monitor.contains("private func sendColorWhenReady"))
        XCTAssertTrue(monitor.contains("private func applyRuntimeBrightnessWhenReady"))
        XCTAssertTrue(monitor.contains("Task.sleep(for: .milliseconds(50))"))
        XCTAssertTrue(monitor.contains("guard await self.sendPowerWhenReady"))
        XCTAssertTrue(monitor.contains("guard await self.sendColorWhenReady"))
        XCTAssertTrue(monitor.contains("power-up breath baseline"))
    }

    func testHeadlightFedBreathUsesPhysicalPowerEpochAndFastOffCancellation() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private var headlightPowerEpoch"))
        XCTAssertTrue(monitor.contains("headlightAnimatedEpochByID"))
        XCTAssertTrue(monitor.contains("noteHeadlightPowerSeen(id, reason: \"advertisement\")"))
        XCTAssertTrue(monitor.contains("scheduleHeadlightPowerOffEvaluation"))
        XCTAssertTrue(monitor.contains("active headlight Breath cancelled"))
        XCTAssertTrue(monitor.contains("if isHeadlightFedDevice(id)"))
        XCTAssertTrue(monitor.contains("quick OFF -> ON must be allowed to Breath again"))
    }

    func testDoorDayNightChangeIsBrightnessOnlyAndInterruptible() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let block = monitor.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(monitor.contains("Day/night automation changes brightness only"))
        XCTAssertTrue(monitor.contains("cancelBrightnessTransition(for: id)"))
        XCTAssertTrue(monitor.contains("pairedDevice(id).map { (id, $0.runtimeBrightness) }"))
        XCTAssertTrue(monitor.contains("headlight-fed physical power ON → night Door brightness"))
        XCTAssertTrue(monitor.contains("headlight-fed physical power OFF → day Door brightness"))
        XCTAssertFalse(block.isEmpty)
    }

    func testKnownVehicleLightsDoNotUseSixSecondCancelReconnectLoop() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func isKnownVehicleAmbientDevice"))
        XCTAssertTrue(monitor.contains("!self.isKnownVehicleAmbientDevice(trackedID)"))
        XCTAssertTrue(monitor.contains("!self.isKnownVehicleAmbientDevice(id)"))
        XCTAssertTrue(monitor.contains("Never cancel a pending connection merely because one of the"))
    }

    func testOpeningControlPageDoesNotSendColorAndPresetTapSendsOnce() throws {
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(view.contains("@State private var colorPickerReady = false"))
        XCTAssertTrue(view.contains("guard colorPickerReady else { return }"))
        XCTAssertTrue(view.contains("DispatchQueue.main.async { colorPickerReady = true }"))
        XCTAssertTrue(view.contains("do not double-send a preset tap"))
    }
}
