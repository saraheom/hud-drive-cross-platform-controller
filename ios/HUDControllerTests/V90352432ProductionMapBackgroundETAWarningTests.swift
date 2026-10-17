import XCTest

final class V90352432ProductionMapBackgroundETAWarningTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMapModeOwnsMainVideoAndMapSurvivesRouteEnd() throws {
        let app = try source("HUDController/App/AppState.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertFalse(app.contains(#"mainVideo.start(reason: "app-only live preview")"#))
        XCTAssertTrue(app.contains(#"self.mainVideo.start(reason: "physical Map Mode live source (optional)")"#))
        XCTAssertTrue(app.contains(#"mainVideo.stop(reason: "live U2W Map Mode disabled — Map Mode owns MainVideo")"#))
        XCTAssertFalse(ui.contains("Start Live Preview (app only)"))
        XCTAssertTrue(canvas.contains("if settings.showMap {"))
        XCTAssertFalse(canvas.contains("settings.showMap && snapshot.hasLiveRoute"))
        XCTAssertTrue(canvas.contains("if snapshot.hasLiveRoute {"))
    }

    func testLockInvalidSessionUsesV840RetainedHistoryRecovery() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(settings.contains("backgroundProbeMode = .keepDecoderBackgroundTask"))
        XCTAssertTrue(app.contains("mainVideo.configureBackgroundProbe(mode: .keepDecoderBackgroundTask)"))
        XCTAssertTrue(video.contains("lock-time -12903 detected"))
        XCTAssertTrue(video.contains(#"restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")"#))
        XCTAssertTrue(video.contains("startupSnapshotFetchTask"))
        XCTAssertTrue(video.contains("readOnlyRebootstrapCooldown"))
        XCTAssertFalse(ui.contains("Map Mode Background Continuity Probe"))
        XCTAssertFalse(ui.contains("Apply for next Map Mode session"))
    }

    func testSharedETAUsesActualCustomLaneRendererVisibility() throws {
        let app = try source("HUDController/App/AppState.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        XCTAssertTrue(app.contains("laneGuidanceVisible: shouldDisplayActiveLanes()"))
        XCTAssertTrue(app.contains("frozen.laneGuidanceVisible = shouldDisplayActiveLanes()"))
        XCTAssertTrue(canvas.contains("settings.showLaneGuidance && snapshot.laneGuidanceVisible && !effectiveLaneValues.isEmpty"))
        XCTAssertTrue(canvas.contains("return !laneGuidanceAvailable"))
        XCTAssertTrue(canvas.contains("settings.etaUsesLanePositionWhenNoLanes ? .lanes : .eta"))
    }

    func testTurnDistanceWarningSharesSpeedTextColor() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        let snapshot = try source("HUDController/MapMode/HudMapModeSnapshot.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(route.contains("private(set) var distanceToManeuverMeters = 0"))
        XCTAssertTrue(snapshot.contains("distanceToManeuverMeters"))
        XCTAssertTrue(canvas.contains("turnDistanceWarningActive"))
        XCTAssertTrue(canvas.contains("warningTextColor"))
        XCTAssertTrue(ui.contains("Turn distance warning"))
        XCTAssertTrue(ui.contains("Warning text color"))
        XCTAssertFalse(ui.contains("Blink count"))
    }
}
