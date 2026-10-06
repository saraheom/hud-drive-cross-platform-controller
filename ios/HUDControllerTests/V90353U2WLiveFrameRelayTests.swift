import XCTest
@testable import HUDController

final class V90353U2WLiveFrameRelayTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testRelayClientUsesPersistent15331LengthPrefixedJPEG() throws {
        let relay = try source("HUDController/MapMode/U2WHUDFrameRelayClient.swift")
        XCTAssertTrue(relay.contains("15331"))
        XCTAssertTrue(relay.contains("UInt32(jpeg.count).bigEndian"))
        XCTAssertTrue(relay.contains("packet.append(jpeg)"))
    }

    func testLiveRelayUsesFreshMainVideoWhenAvailableAndUsesMode6() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("sourceMapImage: freshLiveMapImage"))
        XCTAssertTrue(app.contains("physical Map Mode no longer depends on MainVideo readiness"))
        XCTAssertTrue(app.contains("HudCommands.kivicMode(6)"))
        XCTAssertTrue(app.contains("U2W v8.15"))
        XCTAssertFalse(app.contains("status == 1 && !address.isEmpty"))
    }

    func testRelayUIReportsFrameIngress() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        // v90.35.3.10 intentionally removed the old verbose relay heading and
        // folded the controls into the compact Map Mode card. Keep this test
        // aligned with the production UI while still verifying the relay
        // v24.26 removes the disclosure block entirely and keeps only production controls.
        XCTAssertTrue(ui.contains("CarPlay adapter Wi-Fi name"))
        XCTAssertTrue(ui.contains("Enable Map Mode"))
        XCTAssertTrue(ui.contains("Map Mode FPS"))
        XCTAssertTrue(ui.contains("Collect Live Map Diagnostic ZIP (parked)"))
        XCTAssertTrue(ui.contains("state.mainVideo.transportPhase"))
        XCTAssertTrue(ui.contains("Not active"))
        XCTAssertFalse(ui.contains("Status & diagnostics"))
        XCTAssertFalse(ui.contains("Frame ingress"))
        XCTAssertFalse(ui.contains("Frames sent"))
        XCTAssertFalse(ui.contains("Live iPhone → U2W → HUD relay"))
    }
}
