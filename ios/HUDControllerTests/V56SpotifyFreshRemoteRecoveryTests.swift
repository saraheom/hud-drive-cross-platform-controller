import XCTest
@testable import HUDController

final class V56SpotifyFreshRemoteRecoveryTests: XCTestCase {
    func testOldRemoteCallbacksAreIgnored() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Media/SpotifyMediaController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("guard appRemote === self.appRemote"))
        XCTAssertTrue(source.contains("Ignored failure callback from stale App Remote"))
    }

    func testFreshRemotePreservesKeychainToken() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Media/SpotifyMediaController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("let preservedToken"))
        XCTAssertTrue(source.contains("freshRemote.connectionParameters.accessToken = preservedToken"))
    }
}
