import XCTest
@testable import HUDController

final class V53ProbeCleanupTests: XCTestCase {
    func testExperimentalPersistentTextProbeIsRemoved() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let appState = try String(
            contentsOf: root.appendingPathComponent("HUDController/App/AppState.swift"),
            encoding: .utf8
        )
        let mediaView = try String(
            contentsOf: root.appendingPathComponent("HUDController/UI/MediaView.swift"),
            encoding: .utf8
        )
        let commands = try String(
            contentsOf: root.appendingPathComponent("HUDController/Protocol/HudCommands.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appState.contains("HudTextRendererProbe"))
        XCTAssertFalse(appState.contains("textProbe"))
        XCTAssertFalse(mediaView.contains("Persistent Text / Music Probe"))
        XCTAssertFalse(mediaView.contains("textProbe"))
        XCTAssertFalse(commands.contains("textNotificationProbe"))
        XCTAssertFalse(commands.contains("persistentNavigationTextProbe"))
    }
}
