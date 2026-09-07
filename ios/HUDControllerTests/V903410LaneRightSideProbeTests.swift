import XCTest

final class V903410LaneRightSideProbeTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testLanePlacementModesArePersistedAndDefaultToStockCenter() throws {
        let settings = try source("HUDController/Models/HudSettings.swift")
        XCTAssertTrue(settings.contains("enum HudLanePlacementMode"))
        XCTAssertTrue(settings.contains("case centerNative"))
        XCTAssertTrue(settings.contains("case rightNavigationProbe"))
        XCTAssertTrue(settings.contains("case rightNaviMiniProbe"))
        XCTAssertTrue(settings.contains("HUD.Settings.lanePlacementMode"))
        XCTAssertTrue(settings.contains("HudLanePlacementMode.centerNative.rawValue"))
    }

    func testRightProbeIsStockOnlyAndRestoresNormalNavigation() throws {
        let appState = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(appState.contains("activateRightLaneWidgetProbeIfNeeded"))
        XCTAssertTrue(appState.contains("center: \"Navigation\""))
        XCTAssertTrue(appState.contains("right: rightWidget"))
        XCTAssertTrue(appState.contains("obd.applyNavigationWidgets()"))
        XCTAssertTrue(appState.contains("stock-only/no filesystem write"))

        let start = try XCTUnwrap(appState.range(of: "private func activateRightLaneWidgetProbeIfNeeded"))
        let end = try XCTUnwrap(appState.range(of: "private func restoreNormalNavigationAfterLaneProbeIfNeeded"))
        let probe = String(appState[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(probe.contains("HudCommands.dashboard"))
        XCTAssertFalse(probe.contains("/system"))
        XCTAssertFalse(probe.contains("adb."))
        XCTAssertFalse(probe.contains("maintenance"))
    }

    func testNavigationUIExposesOnlyFocusedLanePlacementProbe() throws {
        let view = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertTrue(view.contains("Picker(\"Lane placement\""))
        XCTAssertTrue(view.contains("Right-side probe keeps the normal center Navigation renderer"))
        XCTAssertFalse(view.contains("Manual navigation diagnostics"))
        XCTAssertFalse(view.contains("Firmware-native lane guidance"))
        XCTAssertTrue(view.contains("Recorded CarPlay lane replay"))
        XCTAssertFalse(view.contains("Ambient-light test build"))
    }
}
