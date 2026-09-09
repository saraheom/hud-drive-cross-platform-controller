import XCTest
@testable import HUDController

final class V903414NativeSpeedMarkerAmbientColorRestoreTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testNativeMarkerUsesOriginalDisplaySpeedWarningPacket() throws {
        let commands = try source("HUDController/Protocol/HudCommands.swift")
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(commands.contains("static func speedWarningThreshold(_ value: Int)"))
        XCTAssertTrue(commands.contains("command: 2, p1: 9, p2: 9"))
        XCTAssertTrue(speed.contains("func reassertOriginalSpeedMarker(reason: String)"))
        XCTAssertTrue(speed.contains("sendOriginalAutomaticSpeedWarning(legalLimitMph: currentSpeedLimitMph)"))
        XCTAssertTrue(speed.contains("DisplaySpeedWarning threshold"))
    }

    func testNavigationRendererSwapReassertsMarker() throws {
        let nav = try source("HUDController/Navigation/HudNavigationController.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(nav.contains("onNavigationModeChanged?(true)"))
        XCTAssertTrue(nav.contains("onNavigationModeChanged?(false)"))
        XCTAssertTrue(app.contains("navigation.onNavigationModeChanged"))
        XCTAssertTrue(app.contains("Task.sleep(for: .milliseconds(150))"))
        XCTAssertTrue(app.contains("reassertOriginalSpeedMarker"))
    }

    func testColorChangeRestoresSemanticBrightnessTarget() throws {
        let ambient = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(ambient.contains("manualColorBrightnessRestoreSeconds: TimeInterval = 1.0"))
        XCTAssertTrue(ambient.contains("restorePreferredBrightnessAfterManualColor"))
        XCTAssertTrue(ambient.contains("let target = steadyBrightnessTarget(for: device)"))
        XCTAssertTrue(ambient.contains("pairedDevices[index].lastAppliedBrightness = 100"))
        XCTAssertTrue(ambient.contains("over: manualColorBrightnessRestoreSeconds"))
    }

    func testGroupColorUsesPerMemberColorPath() throws {
        let ambient = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(ambient.contains("for id in group.memberIDs { setColor(id, color: color) }"))
    }

    func testVehicleUIShowsNativeMarkerState() throws {
        let ui = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(ui.contains("LabeledContent(\"Native speed marker\""))
        XCTAssertTrue(ui.contains("nativeSpeedMarkerStatus"))
        XCTAssertTrue(ui.contains("temporary probe"))
    }
}
