import XCTest
@testable import HUDController

final class V903515SafeMainVideoTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMainVideoRecoveryIsConservativeForSanitizedStream() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("decoderStaleFrameInterval: TimeInterval = 20.0"))
        XCTAssertTrue(video.contains("sourceStaleInterval: TimeInterval = 60.0"))
        XCTAssertTrue(video.contains("decoderStaleDiagnosticCooldown: TimeInterval = 30.0"))
        XCTAssertTrue(video.contains("KEEP decoder session and continue validated P-frames"))
        XCTAssertTrue(video.contains("decoderLiveEdgeReseedInterval: TimeInterval = 90.0"))
        XCTAssertTrue(video.contains("H264MainVideoSanitizer"))
    }

    func testRouteInactiveNeedsFiveSecondsBeforeFreeride() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        XCTAssertTrue(route.contains("inactiveRouteEndConfirmationInterval: TimeInterval = 5.0"))
        XCTAssertTrue(route.contains("inactiveStartedAtBySource"))
        XCTAssertTrue(route.contains("holding active HUD guidance for 5s"))
    }

    func testItem10MapModeProbeIsRetiredFromUI() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertFalse(ui.contains("Native OBD speed test"))
        XCTAssertTrue(app.contains("suppressCustomSpeedForNativeOBDProbe: false"))
    }
}
