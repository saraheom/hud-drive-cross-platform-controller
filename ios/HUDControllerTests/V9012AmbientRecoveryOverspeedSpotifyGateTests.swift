import XCTest
@testable import HUDController

/// Compatibility filename retained so overlay-style repository updates overwrite
/// older v90.12/v90.13 assertions instead of leaving stale tests in GitHub.
final class V9012AmbientRecoveryOverspeedSpotifyGateTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testStableTwoLightSignalOwnsOnlyDayNightAndHUDBrightness() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private enum HeadlightConsensusObservation"))
        XCTAssertTrue(monitor.contains("headlightConsensusStabilitySeconds: TimeInterval = 0.75"))
        XCTAssertTrue(monitor.contains("Two-light day/night consensus"))
        XCTAssertTrue(monitor.contains("Headlight consensus → Auto brightness ON"))
        XCTAssertTrue(monitor.contains("Headlight consensus → Auto brightness OFF"))
    }

    func testPowerOnBreathIsIndependentAndCanBeUnsynchronized() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("var synchronizePowerOnBreathEnabled: Bool"))
        XCTAssertTrue(monitor.contains("startIndividualBreathSession"))
        XCTAssertTrue(monitor.contains("Optional sync window armed for"))
        XCTAssertTrue(monitor.contains("Sync window already closed; starting complete independent Breath"))
        XCTAssertTrue(monitor.contains("every controller return is a brand-new power-on event"))
    }

    func testOverspeedAndSpotifyIndependentFeaturesRemain() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let spotify = try source("HUDController/Media/SpotifyMediaController.swift")
        XCTAssertTrue(monitor.contains("overspeedWarningCooldownSeconds: TimeInterval = 60.0"))
        XCTAssertTrue(monitor.contains("let threshold = speedLimitMph + offset"))
        XCTAssertTrue(spotify.contains("Automatic Spotify app wake suppressed outside vehicle session"))
    }

    func testNoV9013RepeatedRecoveryLoopReturns() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertFalse(monitor.contains("scheduleRobustSteadyStateRecovery"))
        XCTAssertFalse(monitor.contains("rounds=3"))
        XCTAssertFalse(monitor.contains("BLEDIM10Hz"))
    }
}
