import XCTest

final class V90352429StartupBootstrapFullCanvasTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testReleasePairsReadOnlyV838WithUnchangedTransport() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.29"))
        XCTAssertTrue(app.contains("v8.38 Read-Only Startup Bootstrap"))
        XCTAssertTrue(video.contains("v90.35.3.24.29 MainVideo client for U2W v8.38 read-only startup bootstrap"))
        XCTAssertTrue(video.contains("unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay"))
    }

    func testLiveWorkerAttachesBeforeStartupSnapshotsAreFetched() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("bootstrapPreviousEndpoint"))
        XCTAssertTrue(video.contains("bootstrapCurrentEndpoint"))
        XCTAssertTrue(video.contains("fetchStartupBootstrapSnapshots"))
        XCTAssertTrue(video.contains("startWorker(reason: \"relay confirmed / \\(reason)\", startupBootstrap: true)"))
        XCTAssertTrue(video.contains("STARTUP_BOOTSTRAP_BEGIN"))
        XCTAssertTrue(video.contains("live TCP attached and buffering; fetching read-only previous/current generations"))
        XCTAssertTrue(video.contains("STARTUP_BOOTSTRAP_LIVE_BRIDGE"))
        XCTAssertTrue(video.contains("bootstrapOverlap(currentSnapshot:"))
        XCTAssertTrue(video.contains("previousPairIsCoherent"))
        XCTAssertTrue(video.contains("pair=MISMATCH_OR_UNPROVEN"))
        XCTAssertTrue(video.contains("continuous_join=YES"))
    }

    func testShortBackgroundSwitchPreservesDecoderAndUsesBoundedTask() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let root = try source("HUDController/UI/RootView.swift")
        XCTAssertTrue(root.contains("applicationDidEnterBackground()"))
        XCTAssertTrue(video.contains("beginBackgroundTask(withName: \"HUD Map Mode continuity\")"))
        XCTAssertTrue(video.contains("LIFECYCLE PRESERVE"))
        XCTAssertTrue(video.contains("no decoder rebuild, no sanitizer quarantine, no fresh-IDR requirement"))
    }

    func testRendererUsesOne480x240CanvasWithoutLegacyParentColumns() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        XCTAssertTrue(canvas.contains("frame(width: 480, height: 240)"))
        XCTAssertFalse(canvas.contains("HStack(spacing: 0)"))
        XCTAssertTrue(canvas.contains("designerCanvasPosition(for:"))
        XCTAssertTrue(settings.contains("min(480, max(0"))
        XCTAssertTrue(settings.contains("min(240, max(0"))
        XCTAssertTrue(canvas.contains("mapFadeHorizontal"))
        XCTAssertTrue(canvas.contains("mapFadeVertical"))
    }

    func testETACanShareLaneSlotAndDisappearsFromDesignerSelector() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        XCTAssertTrue(settings.contains("etaUsesLanePositionWhenNoLanes"))
        XCTAssertTrue(canvas.contains("if settings.etaUsesLanePositionWhenNoLanes"))
        XCTAssertTrue(canvas.contains("if !laneGuidanceAvailable"))
        XCTAssertTrue(ui.contains("Use lane-guidance position for ETA when lanes are unavailable"))
        XCTAssertTrue(ui.contains("!(state.mapModeSettings.etaUsesLanePositionWhenNoLanes && $0 == .eta)"))
        XCTAssertTrue(canvas.contains(".position(canvasPoint(.timeLeft))"))
    }
}
