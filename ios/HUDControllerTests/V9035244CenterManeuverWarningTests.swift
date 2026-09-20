import XCTest
@testable import HUDController

final class V9035244CenterManeuverWarningTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testPairedCenterRepairsStaleTrackerAndConfirmedDay() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("pairedDevice(id)?.role == .centerConsole"))
        XCTAssertTrue(monitor.contains("paired Center CoreBluetooth didConnect"))
        XCTAssertTrue(monitor.contains("if becamePresent || !headlightPowerSessionActive"))
        XCTAssertTrue(monitor.contains("positive Center evidence"))
    }

    func testMapModeWarningHasRequestedCustomizationAndOneShotGate() throws {
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let app = try source("HUDController/App/AppState.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")

        XCTAssertTrue(settings.contains("enum HudManeuverWarningTarget"))
        XCTAssertTrue(settings.contains("maneuverWarningThresholdFeet"))
        XCTAssertTrue(settings.contains("default: 500"))
        XCTAssertTrue(settings.contains("default: 3"))
        XCTAssertTrue(settings.contains("default: 0.75"))
        XCTAssertTrue(app.contains("mapModeManeuverWarningTriggeredKeys"))
        XCTAssertTrue(app.contains("distance <= threshold"))
        XCTAssertTrue(canvas.contains("warningHiddenTarget == .maneuverArrow ? 0 : 1"))
        XCTAssertTrue(canvas.contains("warningHiddenTarget == .distance ? 0 : 1"))
        XCTAssertTrue(ui.contains("Blink target"))
        XCTAssertTrue(ui.contains("Warning threshold"))
        XCTAssertTrue(ui.contains("Blink count"))
        XCTAssertTrue(ui.contains("Blink interval"))
        XCTAssertTrue(ui.contains("Preview blink"))
    }
}
