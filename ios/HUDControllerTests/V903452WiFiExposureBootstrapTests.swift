import XCTest
@testable import HUDController

final class V903452WiFiExposureBootstrapTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testWiFiExposureUsesIOSCastBootstrapThenIOSHUDMode() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func enableHUDWiFiExposure()")?.lowerBound,
              let end = app.range(of: "func holdHUDWiFiCastingModeForDiagnostics", range: start..<app.endIndex)?.lowerBound else {
            XCTFail("Wi-Fi exposure block missing")
            return
        }
        let block = String(app[start..<end])
        let hotspot = try XCTUnwrap(block.range(of: "hudHotspotBaseband(is5G: false, forceEnable: true)"))
        let cast = try XCTUnwrap(block.range(of: "HudCommands.kivicMode(5)"))
        let hud = try XCTUnwrap(block.range(of: "HudCommands.kivicMode(4)"))
        XCTAssertLessThan(hotspot.lowerBound, cast.lowerBound)
        XCTAssertLessThan(cast.lowerBound, hud.lowerBound)
        XCTAssertTrue(block.contains(".milliseconds(1800)"))
        XCTAssertFalse(block.contains("softwareUpdate"))
        XCTAssertFalse(block.contains("URLSession"))
    }

    func testDisableRestoresIOSHUDModeAndReleasesForcedAP() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func disableHUDWiFiExposure")?.lowerBound else {
            XCTFail("disable Wi-Fi exposure missing")
            return
        }
        let block = String(app[start...].prefix(1600))
        XCTAssertTrue(block.contains("hudHotspotBaseband(is5G: false, forceEnable: false)"))
        XCTAssertTrue(block.contains("HudCommands.kivicMode(4)"))
    }

    func testDiagnosticModeFiveControlsRemainTemporaryAndBLEOnly() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertTrue(app.contains("holdHUDWiFiCastingModeForDiagnostics"))
        XCTAssertTrue(app.contains("returnHUDRendererKeepingWiFi"))
        XCTAssertTrue(ui.contains("Hold Cast Mode 5"))
        XCTAssertTrue(ui.contains("Return HUD Mode 4"))
        XCTAssertFalse(app.contains("HudCommands.softwareUpdate"))
    }
}
