import XCTest
@testable import HUDController

final class SpotifyAutoConnectTests: XCTestCase {
    func testSpotifyAuthorizationIsRestoredFromKeychain() throws {
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

    func testNormalReconnectNeverClearsAuthorization() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Media/SpotifyMediaController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let start = source.range(of: "func connectOrAuthorize()"),
              let end = source.range(of: "func reauthorize()", range: start.upperBound..<source.endIndex)
        else {
            XCTFail("Spotify connect/reauthorize methods not found")
            return
        }

        let normalConnect = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(normalConnect.contains("SpotifyTokenStore.clear()"))
        XCTAssertFalse(normalConnect.contains("accessToken = nil"))

        let reauthorizeTail = String(source[end.lowerBound...])
        XCTAssertTrue(reauthorizeTail.contains("SpotifyTokenStore.clear()"))
        XCTAssertTrue(reauthorizeTail.contains("accessToken = nil"))
    }

    func testReconnectBackoffContinuesAtFifteenSeconds() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Media/SpotifyMediaController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("let delays: [Double] = [2, 5, 10, 15]"))
        XCTAssertTrue(source.contains("delays[min(reconnectAttempt, delays.count - 1)]"))
        XCTAssertTrue(source.contains("self.autoConnectIfPossible()"))
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

    func testMediaViewOnlyShowsAuthorizationAsExceptionalPath() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/UI/MediaView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("Connect / Re-authorize Spotify"))
        XCTAssertTrue(source.contains("Authorize Spotify"))
        XCTAssertTrue(source.contains("Automatic reconnect is active"))
    }
}
