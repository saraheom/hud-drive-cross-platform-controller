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
        XCTAssertTrue(video.contains("localDecoderResyncCooldown: TimeInterval = 30.0"))
        XCTAssertTrue(video.contains("requestDecoderResync"))
        XCTAssertTrue(video.contains("raw HTTP stream left open"))
        XCTAssertTrue(video.contains("H264MainVideoSanitizer"))
    }

    func testRouteInactiveNeedsFiveSecondsBeforeFreeride() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        XCTAssertTrue(route.contains("inactiveRouteEndConfirmationInterval: TimeInterval = 5.0"))
        XCTAssertTrue(route.contains("inactiveStartedAtBySource"))
        XCTAssertTrue(route.contains("holding active HUD guidance for 5s"))
    }

    func testOBDProbeCanStartBeforeConnectionConfirmation() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(app.contains("hudU2WNativeOBDProbePending"))
        XCTAssertTrue(app.contains("Date().addingTimeInterval(20.0)"))
        XCTAssertTrue(app.contains("obd.connect(force: true)"))
        XCTAssertFalse(ui.contains("!state.obd.connected || state.hudU2WNativeOBDProbeActive"))
    }
}
