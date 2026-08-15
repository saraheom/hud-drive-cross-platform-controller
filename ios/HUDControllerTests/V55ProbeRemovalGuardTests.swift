import XCTest
@testable import HUDController

final class V55ProbeRemovalGuardTests: XCTestCase {
    func testRuntimeSourcesDoNotReferenceRemovedProbe() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let iosRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let paths = [
            "HUDController/App/AppState.swift",
            "HUDController/UI/MediaView.swift",
            "HUDController/Protocol/HudCommands.swift"
        ]

        for path in paths {
            let source = try String(
                contentsOf: iosRoot.appendingPathComponent(path),
                encoding: .utf8
            )

            XCTAssertFalse(source.contains("HudTextRendererProbe"))
            XCTAssertFalse(source.contains("textProbe"))
            XCTAssertFalse(source.contains("textNotificationProbe"))
            XCTAssertFalse(source.contains("persistentNavigationTextProbe"))
        }
    }
}
