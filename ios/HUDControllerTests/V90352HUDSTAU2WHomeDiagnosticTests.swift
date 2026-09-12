import XCTest
@testable import HUDController

final class V90352HUDSTAU2WHomeDiagnosticTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testStockWifiSTAModePacketEncoding() {
        let packet = HudCommands.wifiSTAMode(ssid: "NISSAN68", password: "test", security: 2)
        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("STA packet did not unescape")
            return
        }
        XCTAssertEqual(Data(body.prefix(3)), Data([0x02, 0x10, 0x00]))
        XCTAssertNotNil(body.range(of: Data("NISSAN68".utf8)))
        XCTAssertNotNil(body.range(of: Data("test".utf8)))
        XCTAssertEqual(Data(body.suffix(4)), Data([0x00, 0x00, 0x00, 0x02]))
        XCTAssertEqual(HudProtocol.unescape(HudCommands.wifiSTAStatusRequest()), Data([0x02, 0x11, 0x00]))
    }

    func testMode6HomeProbeAndSTAEventParserArePresent() throws {
        let app = try source("HUDController/App/AppState.swift")
        let bt = try source("HUDController/Bluetooth/HudBluetoothManager.swift")
        XCTAssertTrue(app.contains("HudCommands.kivicMode(6)"))
        XCTAssertTrue(app.contains("u2whud-start.cgi"))
        XCTAssertTrue(app.contains("requestHUDU2WSTAStatus"))
        XCTAssertTrue(bt.contains("body[0] == 3, body[1] == 6, body[2] == 0"))
        XCTAssertTrue(bt.contains("onWiFiSTAStatusEvent"))
    }

    func testNavigationAccentRestoredAndTemporarySpeedProbeUIRemoved() throws {
        let nav = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        let mapUI = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let vehicle = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(nav.contains(".tint(HudTheme.accent)"))
        XCTAssertTrue(mapUI.contains("private let accent = HudTheme.accent"))
        XCTAssertFalse(vehicle.contains("SPEED MARKER PROBE — TEMPORARY"))
        XCTAssertFalse(vehicle.contains("D0 — Gauge ON"))
    }
}
