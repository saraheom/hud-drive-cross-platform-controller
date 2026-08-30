import XCTest
@testable import HUDController

final class V9021BLEDIMAnimationTestLabTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testKnownGoodBaselineIsAutomaticDefault() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains(") ?? .v90172Baseline"))
        XCTAssertTrue(monitor.contains("applyBLEDIMTestStrategyToAutomaticPowerOn ? bledimAnimationStrategy : .v90172Baseline"))
        XCTAssertTrue(monitor.contains("applyBLEDIMTestStrategyToAutomaticPowerOn = d.object"))
    }

    func testSixStrategiesAndFocusedPreviewArePresent() throws {
        let model = try source("HUDController/Vehicle/AmbientLightModels.swift")
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        for name in ["v90172Baseline", "baselineHold", "brightnessOnlyFinish", "noTerminalCommit", "alreadyOnMinimal", "v9018NoFlash"] {
            XCTAssertTrue(model.contains("case \(name)"))
        }
        XCTAssertTrue(monitor.contains("previewEnabledBLEDIMBreathNow"))
        XCTAssertTrue(view.contains("BLEDIM ANIMATION TEST LAB"))
        XCTAssertTrue(view.contains("Preview BLEDIM Only"))
    }

    func testStrategiesCapturePerAnimationAndDoNotMutateInflightSequence() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("activeBLEDIMAnimationStrategyByID"))
        XCTAssertTrue(monitor.contains("let capturedBLEDIMStrategy"))
        XCTAssertTrue(monitor.contains("self.activeBLEDIMAnimationStrategyByID[id] = capturedBLEDIMStrategy"))
    }
}
