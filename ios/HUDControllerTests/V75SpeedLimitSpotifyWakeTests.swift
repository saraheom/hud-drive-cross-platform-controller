import XCTest
@testable import HUDController

final class V75SpeedLimitSpotifyWakeTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testSpeedLimitDisplayPacketAlwaysUsesZeroTolerance() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )

        XCTAssertTrue(
            source.contains("HudCommands.speedLimit(limit: 0, tolerance: 0)")
        )
        XCTAssertTrue(
            source.contains("limit: currentSpeedLimitMph,\n                tolerance: 0")
        )
        XCTAssertTrue(
            source.contains("HudCommands.speedLimit(limit: limit, tolerance: 0)")
        )
    }

    func testOverspeedWarningStillUsesUserTolerance() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )

        XCTAssertTrue(
            source.contains(
                "HudCommands.speedWarningThreshold(currentSpeedLimitMph + speedTolerance)"
            )
        )
        XCTAssertTrue(
            source.contains(
                "HudCommands.speedWarningThreshold(limit + speedTolerance)"
            )
        )
    }

    func testSpotifyWakeDoesNotClearSavedAuthorization() throws {
        let source = try source(
            "HUDController/Media/SpotifyMediaController.swift"
        )

        guard let start = source.range(
            of: "func openSpotifyAndResumeConnection()"
        ),
        let end = source.range(
            of: "func reauthorize()",
            range: start.upperBound..<source.endIndex
        ) else {
            XCTFail("Spotify wake method not found")
            return
        }

        let wake = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(wake.contains("authorizeAndPlayURI(\"\")"))
        XCTAssertTrue(wake.contains("restoreTokenFromKeychain()"))
        XCTAssertFalse(wake.contains("SpotifyTokenStore.clear()"))
        XCTAssertFalse(wake.contains("accessToken = nil"))
    }

    func testOnlyResetAuthorizationClearsSpotifyToken() throws {
        let source = try source(
            "HUDController/Media/SpotifyMediaController.swift"
        )

        guard let start = source.range(of: "func reauthorize()"),
              let end = source.range(
                of: "private func beginAuthorization()",
                range: start.upperBound..<source.endIndex
              )
        else {
            XCTFail("Reauthorization method not found")
            return
        }

        let reset = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(reset.contains("SpotifyTokenStore.clear()"))
        XCTAssertTrue(reset.contains("accessToken = nil"))
    }
}
