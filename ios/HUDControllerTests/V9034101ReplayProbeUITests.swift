import XCTest

final class V9034101ReplayProbeUITests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testParkedReplayUIIsRestoredOnlyForLaneProbe() throws {
        let view = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertTrue(view.contains("Recorded CarPlay lane replay"))
        XCTAssertTrue(view.contains("Send This Recorded Step"))
        XCTAssertTrue(view.contains("Auto Replay • 4 s/step"))
        XCTAssertTrue(view.contains("Parked diagnostic for the lane-placement probe"))
        XCTAssertFalse(view.contains("Ambient-light test build"))
        XCTAssertFalse(view.contains("Manual navigation diagnostics"))
        XCTAssertFalse(view.contains("Firmware-native lane guidance"))
    }

    func testReplayUsesLiveLanePolicySoRightProbeCanBeObservedAtHome() throws {
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
        XCTAssertTrue(app.contains("activateRightLaneWidgetProbeIfNeeded"))
    }
}
