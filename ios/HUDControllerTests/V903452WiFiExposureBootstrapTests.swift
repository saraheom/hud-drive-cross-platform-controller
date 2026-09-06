import XCTest
@testable import HUDController

final class V903452WiFiExposureBootstrapTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testWiFiExposureMatchesCapturedStockFiveGHzModeFiveBootstrap() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func enableHUDWiFiExposure()")?.lowerBound,
              let end = app.range(of: "func holdHUDWiFiCastingModeForDiagnostics", range: start..<app.endIndex)?.lowerBound else {
            XCTFail("Wi-Fi exposure block missing")
            return
        }
        let block = String(app[start..<end])
        let hotspot = try XCTUnwrap(block.range(of: "hudHotspotBaseband(is5G: true, forceEnable: false)"))
        let cast = try XCTUnwrap(block.range(of: "HudCommands.kivicMode(5)"))
        XCTAssertLessThan(hotspot.lowerBound, cast.lowerBound)
        XCTAssertTrue(block.contains(".milliseconds(5000)"))
        XCTAssertFalse(block.contains("HudCommands.kivicMode(4)"))
        XCTAssertFalse(block.contains("softwareUpdate"))
        XCTAssertFalse(block.contains("URLSession"))
    }

    func testDisableMatchesCapturedStockOffTransition() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func disableHUDWiFiExposure")?.lowerBound else {
            XCTFail("disable Wi-Fi exposure missing")
            return
        }
        let block = String(app[start...].prefix(1800))
        XCTAssertTrue(block.contains("hudHotspotBaseband(is5G: true, forceEnable: false)"))
        XCTAssertTrue(block.contains("HudCommands.kivicMode(4)"))
    }

    func testDiagnosticAPPinIsSeparateFromStockBootstrap() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        guard let start = app.range(of: "func returnHUDRendererKeepingWiFi")?.lowerBound,
              let end = app.range(of: "func disableHUDWiFiExposure", range: start..<app.endIndex)?.lowerBound else {
            XCTFail("AP pin diagnostic missing")
            return
        }
        let block = String(app[start..<end])
        let pin = try XCTUnwrap(block.range(of: "hudHotspotBaseband(is5G: true, forceEnable: true)"))
        let hud = try XCTUnwrap(block.range(of: "HudCommands.kivicMode(4)"))
        XCTAssertLessThan(pin.lowerBound, hud.lowerBound)
        XCTAssertTrue(ui.contains("Hold Cast Mode 5"))
        XCTAssertTrue(ui.contains("Pin AP + Return HUD Mode 4"))
        XCTAssertFalse(app.contains("HudCommands.softwareUpdate"))
    }
}
