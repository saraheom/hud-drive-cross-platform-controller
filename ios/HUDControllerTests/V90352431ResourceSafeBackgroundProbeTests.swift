import XCTest

final class V90352431ResourceSafeBackgroundProbeTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBootstrapIsZeroCopyAndSingleFlight() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        let current = try source("../u2w/v8.40_ResourceSafeBootstrap_v839Session/source/u2wvideo-bootstrap-current.cgi")
        let previous = try source("../u2w/v8.40_ResourceSafeBootstrap_v839Session/source/u2wvideo-bootstrap-previous.cgi")
        XCTAssertTrue(video.contains("startupSnapshotFetchTask"))
        XCTAssertTrue(video.contains("single-flight JOIN"))
        XCTAssertTrue(video.contains("readOnlyRebootstrapCooldown"))
        XCTAssertTrue(current.contains("zero-copy-pinned-inode"))
        XCTAssertTrue(previous.contains("zero-copy-pinned-inode"))
        XCTAssertFalse(current.contains("u2w_v838_bootstrap_current_$$.h264"))
        XCTAssertFalse(previous.contains("u2w_v838_bootstrap_previous_$$.h264"))
    }

    func testProductionBackgroundModeUsesResourceSafeLockRecovery() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertFalse(app.contains("selectMapModeBackgroundProbeMode"))
        XCTAssertFalse(app.contains("applyMapModeBackgroundProbeModeForNextSession"))
        XCTAssertFalse(ui.contains("Apply for next Map Mode session"))
        XCTAssertTrue(ui.contains(#"Decoder: \(state.mainVideo.decoderSummary)"#))
        XCTAssertFalse(ui.contains("Keep decoder + BG task"))
        XCTAssertTrue(video.contains("lock-time -12903 detected"))
        XCTAssertTrue(video.contains(#"restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")"#))
    }

    func testRouteGuidancePublicationPreservesLastGoodFileOnFailure() throws {
        let rgd = try source("../u2w/v8.40_ResourceSafeBootstrap_v839Session/source/u2w_rgd_preload_v840.c")
        XCTAssertTrue(rgd.contains("publish_atomic_full"))
        XCTAssertTrue(rgd.contains("write_full_fd"))
        XCTAssertTrue(rgd.contains("resource_live_json_failures"))
        XCTAssertTrue(rgd.contains("512L*1024L"))
    }

    func testReleasePairingIsV840AndV834V831RemainUnchanged() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertNotNil(app.range(of: #"appVersion=v90\.35\.3\.24\.[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression))
        XCTAssertTrue(app.contains("paired_u2w=v8.40 Resource-Safe Bootstrap + v8.39 Session Boundary Recovery"))
        XCTAssertTrue(video.contains("unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay"))
    }
}
