import XCTest

final class V9034101ReplayProbeUITests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testParkedReplayAndLanePlacementProbeAreRetiredFromNormalUI() throws {
        let view = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertFalse(view.contains("Recorded CarPlay lane replay"))
        XCTAssertFalse(view.contains("Send This Recorded Step"))
        XCTAssertFalse(view.contains("Auto Replay • 4 s/step"))
        XCTAssertFalse(view.contains("Picker(\"Lane placement\""))
        XCTAssertTrue(view.contains("Navigation presentation"))
        XCTAssertFalse(view.contains("Ambient-light test build"))
        XCTAssertFalse(view.contains("Manual navigation diagnostics"))
        XCTAssertFalse(view.contains("Firmware-native lane guidance"))
    }

    func testHistoricalReplayBackendRemainsBLEOnlyAndUnexposed() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "func sendRecordedCarPlayLaneReplayStep")?.lowerBound,
              let end = app.range(of: "// MARK: - Persistent stock music renderer experiment", range: start..<app.endIndex)?.lowerBound else {
            XCTFail("replay sender missing")
            return
        }
        let block = String(app[start..<end])
        XCTAssertTrue(block.contains("navigation.navigationOn()"))
        XCTAssertTrue(block.contains("navigation.send(step.instruction)"))
        XCTAssertTrue(block.contains("setLaneGuidanceForCurrentManeuver"))
        XCTAssertFalse(block.contains("HudCommands.laneGuidance(step.nativeLanes)"))
        XCTAssertFalse(block.contains("adb."))
        XCTAssertFalse(block.contains("/system"))
        XCTAssertTrue(app.contains("activateRightLaneWidgetProbeIfNeeded"))
    }
}
