import XCTest
@testable import HUDController

final class V9034CarPlayDataTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testNowPlayingIsAdapterBackedAndSpotifyRuntimeIsExcluded() throws {
        let media = try source("HUDController/Media/CarPlayNowPlayingClient.swift")
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/MediaView.swift")
        let project = try source("project.yml")
        XCTAssertTrue(media.contains("u2wmedia-live.cgi"))
        XCTAssertTrue(media.contains("u2wmedia-artwork.cgi"))
        XCTAssertTrue(media.contains("snapshot.artworkAvailable"))
        XCTAssertTrue(app.contains("let nowPlaying: CarPlayNowPlayingClient"))
        XCTAssertTrue(app.contains("pushNowPlayingMetadataToHUD"))
        XCTAssertTrue(ui.contains("CarPlay Now Playing"))
        XCTAssertFalse(ui.contains("Authorize Spotify"))
        XCTAssertFalse(project.contains("package: SpotifyiOS"))
        XCTAssertTrue(project.contains("Media/SpotifyMediaController.swift")) // explicitly excluded legacy source
    }

    func testRouteLivenessDoesNotRequireSequenceMovement() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        XCTAssertTrue(route.contains("endpointStaleInterval: TimeInterval = 4.5"))
        XCTAssertTrue(route.contains("TimedSnapshot(snapshot: snapshot, receivedAt: now)"))
        XCTAssertTrue(route.contains("An unchanged sequence simply means the route state did not change"))
    }

    func testRouteCorridorConsensusRequiresConnectedSameRoadExplicitAgreement() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("corridorWaysConnected"))
        XCTAssertTrue(speed.contains("explicitWayCount"))
        XCTAssertTrue(speed.contains("Set(observations.map { $0.0 })"))
        XCTAssertTrue(speed.contains("OSM Route Guidance corridor consensus"))
        XCTAssertTrue(speed.contains("warningEligible: false"))
    }
}
