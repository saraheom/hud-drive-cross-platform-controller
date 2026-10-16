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
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.31"))
        XCTAssertTrue(app.contains("v8.38 Read-Only Startup Bootstrap"))
        XCTAssertTrue(video.contains("v90.35.3.24.31 MainVideo client for U2W v8.40 resource-safe read-only startup bootstrap"))
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

    func testBackgroundProbeAndSessionRecoveryContracts() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let settings = try source("HUDController/Models/HudMapModeSettings.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let app = try source("HUDController/App/AppState.swift")
        let rgd = try source("../u2w/v8.39_SessionBoundaryRecovery_v838Bootstrap/source/u2w_rgd_preload_v839.c")
        let hudStart = try source("../u2w/v8.39_SessionBoundaryRecovery_v838Bootstrap/source/u2whud-start.cgi")

        XCTAssertTrue(settings.contains("case keepDecoderBackgroundTask"))
        XCTAssertTrue(settings.contains("case hardwareDecoderBackgroundTask"))
        XCTAssertTrue(settings.contains("case suspendDecodePreserveStream"))
        XCTAssertTrue(ui.contains("Map Mode Background Continuity Probe"))
        XCTAssertTrue(ui.contains("Prevent Auto-Lock while Map Mode is active"))
        XCTAssertTrue(video.contains("VTSessionCopyProperty"))
        XCTAssertTrue(video.contains("restartWorkerWithReadOnlyBootstrap"))
        XCTAssertTrue(app.contains("setMapModePreventAutoLock"))
        XCTAssertTrue(rgd.contains("rearm_rgd_for_new_wifi_session"))
        XCTAssertTrue(hudStart.contains("fresh_helpers=YES"))
    }

    func testLaneVisibilityAndUnicodeETAContract() throws {
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")
        let snapshot = try source("HUDController/MapMode/HudMapModeSnapshot.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(snapshot.contains("laneGuidanceVisible"))
        XCTAssertTrue(canvas.contains("snapshot.laneGuidanceVisible"))
        XCTAssertTrue(app.contains("state.laneGuidanceShowing"))
        XCTAssertTrue(canvas.contains("\\u{202F}"))
        XCTAssertTrue(canvas.contains("\\u{00A0}"))
        XCTAssertTrue(canvas.contains(".isWhitespace"))
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
        XCTAssertTrue(canvas.contains("private var shouldRenderETA: Bool"))
        XCTAssertTrue(canvas.contains("return !laneGuidanceAvailable"))
        XCTAssertTrue(ui.contains("Use lane-guidance position for ETA when lanes are unavailable"))
        XCTAssertTrue(ui.contains("!(state.mapModeSettings.etaUsesLanePositionWhenNoLanes && $0 == .eta)"))
        XCTAssertTrue(canvas.contains(".position(canvasPoint(.timeLeft))"))
    }
    func testLayoutDesignerUsesTapGridAndSharedETARenderingIsMutuallyExclusive() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let canvas = try source("HUDController/MapMode/HudMapModeCanvas.swift")

        XCTAssertTrue(ui.contains("LazyVGrid("))
        XCTAssertTrue(ui.contains("GridItem(.adaptive(minimum: 104, maximum: 170)"))
        XCTAssertFalse(ui.contains("ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertTrue(ui.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(ui.contains("!(state.mapModeSettings.etaUsesLanePositionWhenNoLanes && $0 == .eta)"))

        XCTAssertTrue(canvas.contains("private var shouldRenderETA: Bool"))
        XCTAssertTrue(canvas.contains("return !laneGuidanceAvailable"))
        XCTAssertTrue(canvas.contains("private var etaCanvasComponent: HudMapDesignerComponent"))
        XCTAssertTrue(canvas.contains("settings.etaUsesLanePositionWhenNoLanes ? .lanes : .eta"))
        XCTAssertTrue(canvas.contains("if shouldRenderETA"))
    }

}
