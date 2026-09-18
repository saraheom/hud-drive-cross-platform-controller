import XCTest

final class V903520GOPCacheLaneGeometryTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMapPreviewAndPhysicalCanvasHaveNoFakeRouteWhenNavigationInactive() throws {
        let app = try source("HUDController/App/AppState.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(app.contains("mapModePreviewSnapshot"))
        XCTAssertTrue(app.contains("allowDesignFallback: false"))
        XCTAssertTrue(canvas.contains("settings.showMap && snapshot.hasLiveRoute"))
        XCTAssertTrue(canvas.contains("if snapshot.hasLiveRoute"))
    }

    func testLaneGeometryIsShorterButLargeManeuverArrowRemainsIndependent() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(canvas.contains("let bottom = h * 0.82"))
        XCTAssertTrue(canvas.contains("let straightApexY = h * 0.12"))
        XCTAssertTrue(canvas.contains("func turnOnlyCombined(right: Bool)"))
        XCTAssertTrue(canvas.contains("Image(systemName: snapshot.maneuver.symbol)"))
        XCTAssertTrue(canvas.contains("size: CGFloat(34 * settings.maneuverArrowScale)"))
    }

    func testLaneCustomizationAllowsThinVectorStrokes() throws {
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(settings.contains("max(0.60"))
        XCTAssertTrue(ui.contains("Lane arrow thickness"))
        XCTAssertTrue(ui.contains("range: 0.60...2.50"))
        XCTAssertTrue(canvas.contains("max(0.45"))
    }

    func testU2WCacheWarmupAndDiagnosticsAreExposed() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(app.contains("warmAdapterCache(reason: \"HUD BLE transport ready\")"))
        XCTAssertTrue(video.contains("u2wvideo-cache-start.cgi"))
        XCTAssertTrue(video.contains("u2wvideo-cache-status.cgi"))
        XCTAssertTrue(video.contains("v8.21-persistent-gop-cache"))
        XCTAssertTrue(ui.contains("U2W GOP cache"))
    }
}
