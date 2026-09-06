import XCTest
@testable import HUDController

final class V90347ActiveLaneResolutionStockWiFiTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testGoogleMapsCursorWobbleDoesNotResetV88LaneSession() throws {
        let app = try source("HUDController/App/AppState.swift")
        let start = try XCTUnwrap(app.range(of: "Google Maps can transiently"))
        let end = try XCTUnwrap(app.range(of: "if state.schemaVersion >= 2", range: start.lowerBound..<app.endIndex))
        let block = String(app[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(block.contains("no cache reset on cursor wobble"))
        XCTAssertFalse(block.contains("clearLaneGuidancePolicy"))
        XCTAssertFalse(block.contains("liveLaneCacheByManeuver.removeAll()"))
    }

    func testHiddenSelectorZeroCannotReplaceLatchedPersistentEvent() throws {
        let app = try source("HUDController/App/AppState.swift")
        let start = try XCTUnwrap(app.range(of: "private func receiveResolvedV88LaneGuidance"))
        let end = try XCTUnwrap(app.range(of: "private func receiveLegacyV87LaneGuidance", range: start.lowerBound..<app.endIndex))
        let block = String(app[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(block.contains("if state.laneGuidanceShowing"))
        XCTAssertTrue(block.contains("hidden selector must never"))
        XCTAssertTrue(block.contains("CARPLAY LANE LATCH"))
        XCTAssertTrue(block.contains("live lane maneuver completed"))
    }

    func testStockWiFiBootstrapAndMaintenanceAreDistinct() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        let enableStart = try XCTUnwrap(app.range(of: "func enableHUDWiFiExposure()"))
        let holdStart = try XCTUnwrap(app.range(of: "func holdHUDWiFiCastingModeForDiagnostics", range: enableStart.lowerBound..<app.endIndex))
        let enable = String(app[enableStart.lowerBound..<holdStart.lowerBound])
        XCTAssertTrue(enable.contains("hudHotspotBaseband(is5G: true, forceEnable: false)"))
        XCTAssertTrue(enable.contains("HudCommands.kivicMode(5)"))
        XCTAssertTrue(enable.contains(".milliseconds(5000)"))
        XCTAssertFalse(enable.contains("HudCommands.kivicMode(4)"))

        XCTAssertFalse(app.contains("returnHUDRendererKeepingWiFi"))
        XCTAssertFalse(app.contains("hudHotspotBaseband(is5G: true, forceEnable: true)"))
        XCTAssertTrue(app.contains("func startFirmwareMaintenance"))
        XCTAssertTrue(ui.contains("Start Firmware Maintenance"))
        XCTAssertFalse(ui.contains("Pin AP + Return HUD Mode 4"))
    }
}
