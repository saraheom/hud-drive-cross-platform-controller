import XCTest
@testable import HUDController

final class V903411DisplaySettingsTests: XCTestCase {
    private func body(_ packet: Data) throws -> Data {
        try XCTUnwrap(HudProtocol.unescape(packet))
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testOriginalLayoutSizeWireShape() throws {
        XCTAssertEqual(
            try body(HudCommands.layoutSize(0.2)),
            Data([2, 14, 0, 0x3E, 0x4C, 0xCC, 0xCD])
        )
    }

    func testOriginalKeyStoneWireShape() throws {
        XCTAssertEqual(
            try body(HudCommands.keyStone(0.1)),
            Data([2, 3, 0, 0x3D, 0xCC, 0xCC, 0xCD])
        )
    }

    func testScalePerspectivePersistAndRehydrate() throws {
        let settings = try source("HUDController/Models/HudSettings.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(settings.contains("HUD.Settings.displayScaleAdjustment"))
        XCTAssertTrue(settings.contains("HUD.Settings.displayPerspectiveAdjustment"))
        XCTAssertTrue(settings.contains("* 0.2 / 100.0"))
        XCTAssertTrue(settings.contains("* 0.1 / 100.0"))
        XCTAssertGreaterThanOrEqual(
            app.components(separatedBy: "applyDisplayCalibration()").count - 1,
            3
        )
    }

    func testSettingsGearAndFirmwareRelocation() throws {
        let rootView = try source("HUDController/UI/RootView.swift")
        let settingsUI = try source("HUDController/UI/HudSettingsView.swift")
        let nav26 = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertTrue(rootView.contains("gearshape.fill"))
        XCTAssertTrue(rootView.contains("HudSettingsView(state: state)"))
        XCTAssertTrue(settingsUI.contains("Original HUDWAY Scale + Perspective"))
        XCTAssertTrue(settingsUI.contains("HUD Firmware Maintenance"))
        XCTAssertFalse(nav26.contains("HUD Firmware Maintenance"))
    }

    func testPerWidgetResearchStaysReadOnlyUntilARealPacketIsFound() throws {
        let settingsUI = try source("HUDController/UI/HudSettingsView.swift")
        let commands = try source("HUDController/Protocol/HudCommands.swift")
        XCTAssertTrue(settingsUI.contains("Per-widget scale / perspective"))
        XCTAssertTrue(settingsUI.contains("no left/center/right widget identifier"))
        XCTAssertFalse(commands.contains("perWidgetScale"))
        XCTAssertFalse(commands.contains("perWidgetPerspective"))
    }
}
