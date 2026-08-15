import XCTest
@testable import HUDController

final class SpotifyAutoConnectTests: XCTestCase {
    private func source() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Media/SpotifyMediaController.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSpotifyAuthorizationRestoresFromKeychain() throws {
        let source = try source()
        XCTAssertTrue(source.contains("SpotifyTokenStore.load()"))
        XCTAssertTrue(source.contains("SpotifyTokenStore.save(token)"))
        XCTAssertTrue(source.contains("restoreTokenFromKeychain()"))
    }

    func testForegroundRebuildsDisconnectedAppRemote() throws {
        let source = try source()
        XCTAssertTrue(source.contains("func appBecameActive()"))
        XCTAssertTrue(source.contains(#"rebuildAppRemote(reason: "app became active while disconnected")"#))
        XCTAssertTrue(source.contains("autoConnectIfPossible()"))
    }

    func testRepeatedFailuresReplaceStaleAppRemoteWithoutClearingToken() throws {
        let source = try source()
        XCTAssertTrue(source.contains("consecutiveConnectionFailures >= 2"))
        XCTAssertTrue(source.contains("rebuildAppRemote("))
        XCTAssertTrue(source.contains("repeated connection failures"))

        guard let schedule = source.range(of: "private func scheduleReconnect(reason: String)"),
              let request = source.range(of: "func requestNotificationPermission()", range: schedule.upperBound..<source.endIndex)
        else {
            XCTFail("Reconnect method not found")
            return
        }

        let reconnectBlock = String(source[schedule.lowerBound..<request.lowerBound])
        XCTAssertFalse(reconnectBlock.contains("SpotifyTokenStore.clear()"))
        XCTAssertFalse(reconnectBlock.contains("accessToken = nil"))
    }

    func testDuplicateConnectionsAreSuppressed() throws {
        let source = try source()
        XCTAssertTrue(source.contains("connectionInFlight"))
        XCTAssertTrue(source.contains("Connect suppressed: Spotify connection already in flight"))
    }

    func testReconnectBackoffContinuesAtFifteenSeconds() throws {
        let source = try source()
        XCTAssertTrue(source.contains("let delays: [Double] = [1, 2, 5, 10, 15]"))
        XCTAssertTrue(source.contains("delays[min(reconnectAttempt, delays.count - 1)]"))
    }

    func testPlayerSubscriptionRetries() throws {
        let source = try source()
        XCTAssertTrue(source.contains("subscribeToPlayerState(attempt: 1)"))
        XCTAssertTrue(source.contains("attempt < 4"))
        XCTAssertTrue(source.contains("self.subscribeToPlayerState(attempt: attempt + 1)"))
    }

    func testOnlyExplicitReauthorizationClearsToken() throws {
        let source = try source()

        guard let start = source.range(of: "func reauthorize()"),
              let end = source.range(of: "private func beginAuthorization()", range: start.upperBound..<source.endIndex)
        else {
            XCTFail("reauthorize method not found")
            return
        }

        let reauth = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(reauth.contains("SpotifyTokenStore.clear()"))
        XCTAssertTrue(reauth.contains("accessToken = nil"))

        guard let autoStart = source.range(of: "func autoConnectIfPossible()"),
              let autoEnd = source.range(of: "func appBecameActive()", range: autoStart.upperBound..<source.endIndex)
        else {
            XCTFail("auto-connect method not found")
            return
        }

        let automatic = String(source[autoStart.lowerBound..<autoEnd.lowerBound])
        XCTAssertFalse(automatic.contains("SpotifyTokenStore.clear()"))
        XCTAssertFalse(automatic.contains("accessToken = nil"))
    }
}
