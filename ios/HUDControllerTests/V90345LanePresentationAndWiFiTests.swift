import XCTest
@testable import HUDController

final class V90345LanePresentationAndWiFiTests: XCTestCase {
    private func body(_ packet: Data) throws -> Data {
        guard let decoded = HudProtocol.unescape(packet) else {
            throw NSError(domain: "V90345LanePresentationAndWiFiTests", code: 1)
        }
        return decoded
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHUDWiFiPacketsMatchCapturedStockAndPinWireShapes() throws {
        XCTAssertEqual(try body(HudCommands.kivicMode(4)), Data([2, 7, 0, 0, 0, 0, 4]))
        XCTAssertEqual(try body(HudCommands.kivicMode(5)), Data([2, 7, 0, 0, 0, 0, 5]))
        XCTAssertEqual(
            try body(HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false)),
            Data([2, 21, 0, 1, 0])
        )
        XCTAssertEqual(
            try body(HudCommands.hudHotspotBaseband(is5G: true, forceEnable: true)),
            Data([2, 21, 0, 1, 1])
        )
    }

    func testLanePolicySupportsCurrentStreetNearTurnAndPersistentModes() throws {
        let settings = try source("HUDController/Models/HudSettings.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(settings.contains("navigationShowCurrentStreet"))
        XCTAssertTrue(settings.contains("case nearTurn"))
        XCTAssertTrue(settings.contains("case persistent"))
        XCTAssertTrue(settings.contains("laneGuidanceDistanceMiles"))
        XCTAssertTrue(app.contains("laneGuidanceRefreshInterval"))
        XCTAssertTrue(app.contains(".milliseconds(1500)"))
        XCTAssertTrue(app.contains("activeLaneDistanceMeters <= laneGuidanceThresholdMeters"))
    }

    func testReplayUsesSameConfigurableLaneCoordinator() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func sendRecordedCarPlayLaneReplayStep")?.lowerBound else {
            XCTFail("recorded replay sender missing")
            return
        }
        let tail = String(app[start...].prefix(1800))
        XCTAssertTrue(tail.contains("navigation.showCurrentStreet = settings.navigationShowCurrentStreet"))
        XCTAssertTrue(tail.contains("setLaneGuidanceForCurrentManeuver"))
        XCTAssertFalse(tail.contains("HudCommands.laneGuidance(step.nativeLanes)"))
    }

    func testIOS26UIKeepsLiveSettingsAndMaintenanceWithoutLegacyDiagnosticPanels() throws {
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        let settingsUI = try source("HUDController/UI/HudSettingsView.swift")
        XCTAssertTrue(ui.contains("Navigation presentation"))
        XCTAssertTrue(ui.contains("Show Current Street"))
        XCTAssertTrue(ui.contains("Lane Guidance"))
        XCTAssertTrue(ui.contains("0.1...1.0"))
        XCTAssertTrue(ui.contains("Recorded CarPlay lane replay"))
        XCTAssertFalse(ui.contains("Manual navigation diagnostics"))
        XCTAssertFalse(ui.contains("Firmware-native lane guidance"))
        XCTAssertFalse(ui.contains("Ambient-light test build"))
        XCTAssertFalse(ui.contains("HUD Firmware Maintenance"))
        XCTAssertTrue(settingsUI.contains("HUD Firmware Maintenance"))
        XCTAssertTrue(settingsUI.contains("Start Firmware Maintenance"))
        XCTAssertTrue(settingsUI.contains("Reconnect ADB"))
        XCTAssertFalse(settingsUI.contains("Pin AP + Return HUD Mode 4"))
        XCTAssertTrue(settingsUI.contains("87654321"))
        XCTAssertTrue(settingsUI.contains("192.168.43.1"))
    }

    func testWiFiExposureNeverEntersFirmwareWriter() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func enableHUDWiFiExposure()")?.lowerBound,
              let end = app.range(of: "func holdHUDWiFiCastingModeForDiagnostics", range: start..<app.endIndex)?.lowerBound else {
            XCTFail("Wi-Fi exposure methods missing")
            return
        }
        let enter = String(app[start..<end])
        XCTAssertTrue(enter.contains("hudHotspotBaseband(is5G: true, forceEnable: false)"))
        XCTAssertTrue(enter.contains("HudCommands.kivicMode(5)"))
        XCTAssertFalse(enter.contains("HudCommands.kivicMode(4)"))
        XCTAssertTrue(enter.contains(".milliseconds(5000)"))
        XCTAssertFalse(enter.contains("HudCommands.softwareUpdate"))
        XCTAssertFalse(enter.contains("URLSession"))
    }
}
