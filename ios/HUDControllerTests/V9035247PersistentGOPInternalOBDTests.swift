import Foundation
import XCTest
@testable import HUDController

final class V9035247PersistentGOPInternalOBDTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func optionalU2WSource(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("U2W source is intentionally absent from the app-only repository package")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testMainVideoAcceptsV826AndAvoidsWaitingReconnectStorm() throws {
        let video = try source("ios/HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("Data(\"U2WH2644\".utf8)"))
        XCTAssertTrue(video.contains("WAITING bootstrap held on same TCP"))
        XCTAssertTrue(video.contains("adapterRelayLastSourceProgressAt"))
        XCTAssertTrue(video.contains("source-silence reconnect SUPPRESSED until real TCP failure/EOF or manual request"))
        XCTAssertTrue(video.contains("startupDecoderGraceFrameCount = 10"))
        XCTAssertTrue(video.contains("startupDecoderGraceInterval: TimeInterval = 8.0"))
    }

    func testV826PreservesCodecAndCacheAcrossStorageGenerationChanges() throws {
        let relay = try optionalU2WSource("u2w/v8.26_PersistentGOPBridge/source/u2w_mainvideo_relay.c")
        XCTAssertTrue(relay.contains("U2WH2644"))
        XCTAssertTrue(relay.contains("source-generation-change-preserve-validator-client-and-gop-cache"))
        XCTAssertTrue(relay.contains("gop_cache_ready="))
        XCTAssertTrue(relay.contains("begin_live_from_cache"))
        XCTAssertTrue(relay.contains("#define CATCHUP_CAP (48*1024*1024)"))
    }

    func testOBDV4UsesHudInternalDiagnosticArchiveAfterRoadPhase() throws {
        let app = try source("ios/HUDController/App/AppState.swift")
        let ui = try source("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(app.contains("startHUDOBDInternalSpeedProbeV4"))
        XCTAssertTrue(app.contains("requestOBDDiagnosticLogs(maxLastFilesCount: 5)"))
        XCTAssertTrue(app.contains("no second OBD connection"))
        XCTAssertTrue(ui.contains("Run 90 s HUD-internal OBD probe v4"))
        XCTAssertTrue(ui.contains("Collect HUD OBD logs (parked)"))
    }
}
