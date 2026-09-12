import XCTest

final class V903538MapUILayoutCalibrationTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testPersistedPhysicalWidgetOffsetsAndRightSideTuningArePresent() throws {
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        for key in [
            "leftOffsetX", "leftOffsetY", "centerOffsetX", "centerOffsetY",
            "rightOffsetX", "rightOffsetY", "maneuverArrowScale",
            "maneuverArrowThickness", "maneuverOffsetX", "maneuverOffsetY",
            "laneScale", "laneArrowThickness", "laneSpacing", "laneActiveEmphasis",
            "laneOffsetX", "laneOffsetY", "etaScale", "etaOffsetX", "etaOffsetY"
        ] {
            XCTAssertTrue(settings.contains(key), "missing \(key)")
        }
        XCTAssertTrue(settings.contains("resetWidgetOffsets"))
        XCTAssertTrue(settings.contains("resetRightComponentOffsets"))
        XCTAssertTrue(settings.contains("resetRightStyling"))
    }

    func testRendererAppliesOffsetsBoldnessAndLaneEmphasisOnlyInJPEGComposition() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(canvas.contains("settings.leftOffsetX"))
        XCTAssertTrue(canvas.contains("settings.centerOffsetX"))
        XCTAssertTrue(canvas.contains("settings.rightOffsetX"))
        XCTAssertTrue(canvas.contains("symbolWeight(settings.maneuverArrowThickness)"))
        XCTAssertTrue(canvas.contains("symbolWeight(settings.laneArrowThickness)"))
        XCTAssertTrue(canvas.contains("settings.laneActiveEmphasis"))
        XCTAssertTrue(canvas.contains("settings.laneSpacing"))
        XCTAssertTrue(canvas.contains("settings.etaOffsetX"))
    }

    func testNavigationUIExposesBoundedTwoPixelNudgesAndStylingControls() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(ui.contains("Physical HUD position"))
        XCTAssertTrue(ui.contains("Right-side maneuver / lane calibration"))
        XCTAssertTrue(ui.contains("Turn arrow boldness"))
        XCTAssertTrue(ui.contains("Lane boldness"))
        XCTAssertTrue(ui.contains("Active lane emphasis"))
        XCTAssertTrue(ui.contains("delta: -2"))
        XCTAssertTrue(ui.contains("delta: 2"))
        XCTAssertTrue(ui.contains("xRange: -20...20"))
        XCTAssertTrue(ui.contains("yRange: -12...12"))
    }

    func testKnownGoodRelaySequenceWasNotChangedForLayoutRevision() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("known-good join sequence: mode 6 once → credentials once → wait"))
        XCTAssertTrue(app.contains("HudCommands.kivicMode(6)"))
        XCTAssertTrue(app.contains("HudCommands.wifiSTAMode"))
    }
}
