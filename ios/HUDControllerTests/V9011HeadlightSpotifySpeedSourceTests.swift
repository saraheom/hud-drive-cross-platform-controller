import XCTest
@testable import HUDController

final class V9011HeadlightSpotifySpeedSourceTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHUDAndDoorUseFastCenterSignalWhileTwoLightCrosscheckRemainsDiagnostic() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private enum HeadlightConsensusObservation"))
        XCTAssertTrue(monitor.contains("Dashboard+Center diagnostic consensus"))
        XCTAssertTrue(monitor.contains("Center presence → Auto brightness ON"))
        XCTAssertTrue(monitor.contains("Center absence → Auto brightness OFF"))
        XCTAssertTrue(monitor.contains("Center present → night Door brightness"))
        XCTAssertTrue(monitor.contains("Center absent → day Door brightness"))
        XCTAssertFalse(monitor.contains("setAuthoritativeHeadlightPower"))
    }

    func testSpotifyWakeIsAutomaticAndPreservesAuthorization() throws {
        let spotify = try source("HUDController/Media/SpotifyMediaController.swift")
        XCTAssertTrue(spotify.contains("private func attemptAutomaticSpotifyWake"))
        XCTAssertTrue(spotify.contains("consecutiveConnectionFailures >= 2"))
        XCTAssertTrue(spotify.contains("Automatic Spotify wake after connect failures"))
        XCTAssertTrue(spotify.contains("appRemote.authorizeAndPlayURI(\"\")"))
        let wake = spotify.components(separatedBy: "private func attemptAutomaticSpotifyWake")[1]
            .components(separatedBy: "private func ensurePlayerStateSubscription")[0]
        XCTAssertFalse(wake.contains("SpotifyTokenStore.clear()"))
        XCTAssertFalse(wake.contains("accessToken = nil"))
    }

    func testThreeNoBillingSpeedLimitSourcesRemainSelectable() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let view = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(speed.contains("case current = \"Current\""))
        XCTAssertTrue(speed.contains("case traceOSM = \"OSM Trace\""))
        XCTAssertTrue(speed.contains("case improvedTracePhilly = \"Improved + Philly GIS\""))
        XCTAssertFalse(speed.contains("case enhancedOSM = \"Enhanced OSM\""))
        XCTAssertFalse(speed.contains("case here = \"HERE\""))
        XCTAssertTrue(view.contains("SpeedLimitSourceMode.allCases"))
        XCTAssertFalse(view.contains("Save HERE Key"))
    }

    func testOSMTraceUsesRollingTraceAndNoCommercialAPI() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("bestTraceSpeedLimit"))
        XCTAssertTrue(speed.contains("traceLocations"))
        XCTAssertTrue(speed.contains("parseSimpleConditionalMaxSpeed"))
        XCTAssertTrue(speed.contains("OSM Trace accepted way="))
        XCTAssertFalse(speed.contains("routematching.hereapi.com"))
        XCTAssertFalse(speed.contains("HereAPIKeyStore"))
    }

    func testV9012OptInOverspeedWarningStillUsesExistingCLLocationSpeed() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let view = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(speed.contains("CLLocation.speed"))
        XCTAssertTrue(view.contains("AMBIENT OVERSPEED WARNING"))
        XCTAssertTrue(view.contains("Offset above limit"))
    }
}
