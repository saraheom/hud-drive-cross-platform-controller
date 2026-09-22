import XCTest

final class V9035246ValidatedGOPRecoveryTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV825UsesValidatedFileGOPAndBoundedCatchup() throws {
        let relay = try source("../u2w/v8.25_ValidatedGOPRecovery/source/u2w_mainvideo_relay.c")
        XCTAssertTrue(relay.contains("#define EXPECT_WIDTH 800"))
        XCTAssertTrue(relay.contains("#define EXPECT_HEIGHT 480"))
        XCTAssertTrue(relay.contains("#define CATCHUP_CAP (48*1024*1024)"))
        XCTAssertTrue(relay.contains("#define CATCHUP_FRAME_PACE_MS 4"))
        XCTAssertTrue(relay.contains("CATCHING_UP_GOP"))
        XCTAssertTrue(relay.contains("catchup_frames="))
        XCTAssertTrue(relay.contains("newest_valid_gop"))
        XCTAssertTrue(relay.contains("file_gop_bootstraps"))
        XCTAssertTrue(relay.contains("generation_reseeds"))
        XCTAssertTrue(relay.contains("validated-gop-catchup-cap-exceeded-wait-live-idr"))
    }

    func testIOSSupportsV824RollbackAndV825Diagnostics() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("relayVersion.contains(\"v8.24\") || relayVersion.contains(\"v8.25\")"))
        XCTAssertTrue(video.contains("U2WH2642"))
        XCTAssertTrue(video.contains("U2WH2643"))
        XCTAssertTrue(video.contains("file_gop_scan_attempts"))
        XCTAssertTrue(video.contains("file_gop_bootstraps"))
        XCTAssertTrue(video.contains("generation_reseeds"))
        XCTAssertTrue(video.contains("catchup_active"))
        XCTAssertTrue(video.contains("catchup_frames"))
        XCTAssertTrue(video.contains("bounded decoder recovery validated-GOP reseed"))
    }

    func testV825InstallerDoesNotReplaceStableCaptureOrHUDRelay() throws {
        let install = try source("../u2w/v8.25_ValidatedGOPRecovery/source/install_once.sh")
        XCTAssertTrue(install.contains("applecarplay_hook_changed=0"))
        XCTAssertTrue(install.contains("route_guidance_changed=0"))
        XCTAssertTrue(install.contains("now_playing_changed=0"))
        XCTAssertTrue(install.contains("hud_cast_relay_changed=0"))
        XCTAssertFalse(install.contains("killall AppleCarPlay"))
        XCTAssertFalse(install.contains("cp \"$P/u2whud_cast_relay"))
    }
}
