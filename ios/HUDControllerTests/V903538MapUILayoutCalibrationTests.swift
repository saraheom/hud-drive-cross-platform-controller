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

    func testRendererUsesAbsoluteCanvasPositionsWhilePreservingStyling() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        XCTAssertTrue(canvas.contains("frame(width: 480, height: 240)"))
        XCTAssertTrue(canvas.contains("designerCanvasPosition(for:"))
        XCTAssertTrue(canvas.contains(".position(canvasPoint(.map))"))
        XCTAssertTrue(canvas.contains(".position(canvasPoint(.lanes))"))
        XCTAssertFalse(canvas.contains("HStack(spacing: 0)"))
        // Legacy offsets remain in settings only as migration/default anchors.
        XCTAssertTrue(settings.contains("return (centerOffsetX, centerOffsetY)"))
        XCTAssertTrue(settings.contains("return (rightOffsetX + laneOffsetX, rightOffsetY + laneOffsetY)"))
        XCTAssertTrue(canvas.contains("symbolWeight(settings.maneuverArrowThickness)"))
        XCTAssertTrue(canvas.contains("LaneGuidanceGlyph("))
        XCTAssertTrue(canvas.contains("settings.laneArrowThickness * 0.82"))
        XCTAssertTrue(canvas.contains("settings.laneActiveEmphasis"))
        XCTAssertTrue(canvas.contains("settings.laneSpacing"))
    }

    func testNavigationUIExposesFullCanvasDesignerAndStylingControls() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(ui.contains("Full-canvas 480×240 layout"))
        XCTAssertTrue(ui.contains("ForEach(designerComponents)"))
        XCTAssertTrue(ui.contains("setDesignerCanvasPosition"))
        XCTAssertTrue(ui.contains("Turn arrow boldness"))
        XCTAssertTrue(ui.contains("Lane arrow thickness"))
        XCTAssertTrue(ui.contains("Active lane emphasis"))
        XCTAssertTrue(ui.contains("Use lane-guidance position for ETA when lanes are unavailable"))
    }

    func testKnownGoodRelaySequenceWasNotChangedForLayoutRevision() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("known-good join sequence: mode 6 once → credentials once → wait"))
        XCTAssertTrue(app.contains("HudCommands.kivicMode(6)"))
        XCTAssertTrue(app.contains("HudCommands.wifiSTAMode"))
    }
}
