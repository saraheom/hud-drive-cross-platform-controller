import XCTest

final class V903517OBDNetworkLaneTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testItem10MapModeProbeIsRetiredAfterNegativeRoadTest() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(ui.contains("Native OBD speed test"))
        XCTAssertTrue(app.contains("suppressCustomSpeedForNativeOBDProbe: false"))
    }

    func testNetworkTraceCoversDefaultWiFiAndCellular() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("import Network"))
        XCTAssertTrue(video.contains("NWPathMonitor(requiredInterfaceType: .wifi)"))
        XCTAssertTrue(video.contains("NWPathMonitor(requiredInterfaceType: .cellular)"))
        XCTAssertTrue(video.contains("IPHONE NETWORK"))
        XCTAssertTrue(video.contains("15s MainVideo heartbeat"))
    }

    func testSpeedLimitSlotAndLaneWindowing() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(canvas.contains("settings.showSpeedLimit && snapshot.speedLimitMph > 0"))
        XCTAssertTrue(canvas.contains("No OSM speed limit = no white rectangle"))
        XCTAssertTrue(canvas.contains("private var displayedLaneValues"))
        XCTAssertTrue(canvas.contains("guard values.count > 4 else { return values }"))
        XCTAssertTrue(canvas.contains("activeInside"))
        XCTAssertTrue(canvas.contains("LaneGuidanceGlyph"))
        XCTAssertTrue(canvas.contains("func combined(right: Bool, drawColor: Color"))
        XCTAssertTrue(canvas.contains("func turnOnlyCombined(right: Bool)"))
        XCTAssertTrue(canvas.contains("uses the approved shorter Google-style lane arrows"))
        XCTAssertTrue(canvas.contains("Combined straight+turn glyphs share one body"))
    }
}
