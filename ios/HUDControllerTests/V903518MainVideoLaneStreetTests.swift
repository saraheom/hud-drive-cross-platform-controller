import XCTest

final class V903518MainVideoLaneStreetTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMainVideoRecoveryDoesNotPoisonDecoderAfterOneError() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("CONTINUE without IDR reset"))
        XCTAssertTrue(video.contains("consecutiveErrorRebuildThreshold = 5"))
        XCTAssertTrue(video.contains("CONTINUE without IDR reset"))
        XCTAssertTrue(video.contains("PRESERVE transport/decoder, no reconnect"))
        XCTAssertFalse(video.contains("requestDecoderResync"))
    }

    func testLaneVectorsAndTwoLineStreetLayout() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(canvas.contains("LaneGuidanceGlyph"))
        XCTAssertTrue(canvas.contains("func combined(right: Bool, drawColor: Color"))
        XCTAssertTrue(canvas.contains("func turnOnlyCombined(right: Bool)"))
        XCTAssertTrue(canvas.contains("laneGlyphStyle(for wireValue: Int)"))
        XCTAssertTrue(canvas.contains("MergeManeuverGlyph"))
        XCTAssertTrue(canvas.contains(".lineLimit(2)"))
        XCTAssertTrue(canvas.contains("minHeight: 29, maxHeight: 29"))
    }

    func testItem10ProbeIsNotExposedInNavigationUI() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertFalse(ui.contains("Native OBD speed test"))
        XCTAssertFalse(ui.contains("obdProbeControls"))
    }
}
