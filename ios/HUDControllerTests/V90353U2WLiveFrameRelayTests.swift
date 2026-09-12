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

    func testLiveRelayKeepsMainVideoLiveAndUsesMode6() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("sourceMapImage: self.mainVideo.latestFrame"))
        XCTAssertTrue(app.contains("HudCommands.kivicMode(6)"))
        XCTAssertTrue(app.contains("U2W v8.15"))
        XCTAssertFalse(app.contains("status == 1 && !address.isEmpty"))
    }

    func testRelayUIReportsFrameIngress() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        // v90.35.3.10 intentionally removed the old verbose relay heading and
        // folded the controls into the compact Map Mode card. Keep this test
        // aligned with the production UI while still verifying the relay
        // diagnostics remain available behind the disclosure control.
        XCTAssertTrue(ui.contains("CarPlay adapter Wi-Fi name"))
        XCTAssertTrue(ui.contains("Enable Map Mode"))
        XCTAssertTrue(ui.contains("Status & diagnostics"))
        XCTAssertTrue(ui.contains("Frame ingress"))
        XCTAssertTrue(ui.contains("Frames sent"))
        XCTAssertTrue(ui.contains("U2W v8.15.1"))
        XCTAssertFalse(ui.contains("Live iPhone → U2W → HUD relay"))
    }
}
