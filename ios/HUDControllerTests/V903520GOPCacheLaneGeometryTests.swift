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
        // v90.35.3.22 made shaft/body length user-adjustable. Guard the new
        // dynamic geometry instead of the retired fixed 0.82 bottom point.
        XCTAssertTrue(canvas.contains("let body = min(1.0, max(0.55, bodyLength))"))
        XCTAssertTrue(canvas.contains("let bottom = h * (0.30 + 0.52 * body)"))
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

    func testDedicatedH264RelayWarmupAndDiagnosticsAreExposed() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertFalse(app.contains("HUD BLE transport ready — early predecode"))
        XCTAssertFalse(app.contains("app session early predecode"))
        XCTAssertTrue(video.contains("u2wvideo-relay-start.cgi"))
        XCTAssertTrue(video.contains("u2wvideo-relay-status.cgi"))
        XCTAssertTrue(video.contains("v8.34-hard-bounded-mirror-v831-raw-tcp-15332"))
        // v24.26 intentionally removes the verbose relay diagnostics from the everyday UI.
        XCTAssertTrue(ui.contains("Map Mode FPS"))
        XCTAssertTrue(ui.contains("Collect Live Map Diagnostic ZIP (parked)"))
        XCTAssertFalse(ui.contains("U2W H.264 relay"))
        XCTAssertTrue(app.contains(#"mainVideo.start(reason: "physical Map Mode live source (optional)")"#))
    }
}
