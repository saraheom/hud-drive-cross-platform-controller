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

    func testMapModeTurnWarningUsesContinuousSharedColorAndThreshold() throws {
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let snapshot = try source("HUDController/MapMode/HudMapModeSnapshot.swift")

        XCTAssertTrue(settings.contains("maneuverWarningThresholdFeet"))
        XCTAssertTrue(settings.contains("default: 500"))
        XCTAssertTrue(snapshot.contains("distanceToManeuverMeters"))
        XCTAssertTrue(canvas.contains("turnDistanceWarningActive"))
        XCTAssertTrue(canvas.contains("snapshot.distanceToManeuverMeters"))
        XCTAssertTrue(canvas.contains(".foregroundStyle(turnDistanceWarningActive ? warningTextColor : .white)"))
        XCTAssertTrue(canvas.contains("speedWarningNumberRed"))
        XCTAssertFalse(canvas.contains("warningHiddenTarget == .maneuverArrow"))
        XCTAssertFalse(canvas.contains("warningHiddenTarget == .distance"))
        XCTAssertTrue(ui.contains("Map Mode Warnings"))
        XCTAssertTrue(ui.contains("Turn distance warning"))
        XCTAssertTrue(ui.contains("Warning below"))
        XCTAssertTrue(ui.contains("Warning text color"))
        XCTAssertFalse(ui.contains("Preview blink"))
    }

}
