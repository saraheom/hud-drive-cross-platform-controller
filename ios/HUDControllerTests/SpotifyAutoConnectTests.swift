import XCTest
@testable import HUDController

final class SpotifyAutoConnectTests: XCTestCase {
    func testSpotifyAutoConnectSourceIsPresent() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Media/SpotifyMediaController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("SpotifyTokenStore.load()"))
        XCTAssertTrue(source.contains("SpotifyTokenStore.save(token)"))
        XCTAssertTrue(source.contains("func autoConnectIfPossible()"))
        XCTAssertTrue(source.contains("appRemote.connect()"))
    }

    func testRootLifecycleReconnectsSpotify() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/UI/RootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("state.spotify.appBecameActive()"))
        XCTAssertTrue(source.contains("state.spotify.appEnteredBackground()"))
    }
}
