import XCTest
@testable import HUDController

final class V9021BLEDIMAnimationTestLabTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV9022PromotesMinimalToAutomaticDefault() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains(") ?? .alreadyOnMinimal"))
        XCTAssertTrue(monitor.contains("? .alreadyOnMinimal"))
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
        XCTAssertFalse(view.contains("BLEDIM ANIMATION TEST LAB"))
        XCTAssertTrue(view.contains("BLEDIM PRODUCTION ANIMATION"))
        XCTAssertTrue(view.contains("Already-On Minimal"))
        XCTAssertTrue(view.contains("Preview BLEDIM Only"))
    }

    func testStrategiesCapturePerAnimationAndDoNotMutateInflightSequence() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("activeBLEDIMAnimationStrategyByID"))
        XCTAssertTrue(monitor.contains("let capturedBLEDIMStrategy"))
        XCTAssertTrue(monitor.contains("self.activeBLEDIMAnimationStrategyByID[id] = capturedBLEDIMStrategy"))
    }
}
