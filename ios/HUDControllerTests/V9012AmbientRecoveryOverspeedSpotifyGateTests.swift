import XCTest
@testable import HUDController

/// Compatibility regression coverage for the v90.14 lighting architecture.
///
/// This filename intentionally remains V9012... because older GitHub checkouts may
/// still contain that test from the v90.12/v90.13 line. Keeping and replacing the
/// file makes overlay-style repository updates converge on the current assertions
/// instead of leaving stale tests behind.
final class V9012AmbientRecoveryOverspeedSpotifyGateTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testSpotifyAutomaticWakeIsVehicleGated() throws {
        let spotify = try source("HUDController/Media/SpotifyMediaController.swift")
        let app = try source("HUDController/App/AppState.swift")
        let root = try source("HUDController/UI/RootView.swift")
        XCTAssertTrue(spotify.contains("guard automaticVehicleWakeAllowed else"))
        XCTAssertTrue(spotify.contains("Automatic Spotify app wake suppressed outside vehicle session"))
        XCTAssertTrue(app.contains("bluetooth.state == .connected || obd.connected"))
        XCTAssertTrue(root.contains("updateSpotifyVehicleWakeGate(reason: \"app became active\")"))
    }

    func testHeadlightStateRequiresStableTwoControllerConsensus() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private enum HeadlightConsensusObservation"))
        XCTAssertTrue(monitor.contains("headlightConsensusStabilitySeconds: TimeInterval = 0.75"))
        XCTAssertTrue(monitor.contains("if dashboardOn && centerOn { return .bothOn }"))
        XCTAssertTrue(monitor.contains("if !dashboardOn && !centerOn { return .bothOff }"))
        XCTAssertTrue(monitor.contains("Headlight consensus candidate=mixed; preserving confirmed"))
        XCTAssertFalse(monitor.contains("setAuthoritativeHeadlightPower"))
    }

    func testHeadlightBreathWaitsForBothWritableControllers() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private func tryStartConfirmedHeadlightBreath"))
        XCTAssertTrue(monitor.contains("dashboardGATTNotReady"))
        XCTAssertTrue(monitor.contains("centerGATTNotReady"))
        XCTAssertTrue(monitor.contains("Consensus headlight animation admitted"))
        XCTAssertTrue(monitor.contains("ready=2"))
    }

    func testSameEpochReconnectUsesSingleSteadyRestoreInsteadOfBreathReplay() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Same-epoch headlight reconnect → steady restore"))
        XCTAssertTrue(monitor.contains("headlightAnimatedEpochByID[id] == headlightPowerEpoch"))
        XCTAssertTrue(monitor.contains("restoreDeviceState(id)"))
        XCTAssertFalse(monitor.contains("scheduleRobustSteadyStateRecovery"))
        XCTAssertFalse(monitor.contains("Steady-state recovery begin"))
    }

    func testOverspeedWarningIsFiniteCrossingOnlyAndRequiresFreshLimit() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(monitor.contains("let threshold = speedLimitMph + offset"))
        XCTAssertTrue(monitor.contains("let above = gpsSpeedMph > threshold"))
        XCTAssertTrue(monitor.contains("let crossedUp = above && !overspeedAboveThreshold"))
        XCTAssertTrue(monitor.contains("speed-limit sign unavailable"))
        XCTAssertTrue(speed.contains("speedLimitAvailableForWarning"))
        XCTAssertTrue(speed.contains("lastResolvedLimitAt"))
    }

    func testOverspeedWarningNeverPowersSelectedLightOff() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let warning = monitor.components(separatedBy: "private func triggerOverspeedWarning")[1]
            .components(separatedBy: "// MARK: - Connection management")[0]
        XCTAssertTrue(warning.contains("sendPowerWhenReady(id, on: true"))
        XCTAssertFalse(warning.contains("sendPowerWhenReady(id, on: false"))
        XCTAssertTrue(warning.contains("restoreAfterOverspeedWarning"))
        XCTAssertTrue(warning.contains("doorTargetBrightness(night: vehicleHeadlightsActive)"))
    }

    func testAsyncValidityHelperRemainsMainActorIsolated() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("@MainActor func stillValid() -> Bool"))
    }

    func testOverspeedConfigurationIsExposed() throws {
        let view = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(view.contains("AMBIENT OVERSPEED WARNING"))
        XCTAssertTrue(view.contains("Warning color"))
        XCTAssertTrue(view.contains("Offset above limit"))
        XCTAssertTrue(view.contains("Warning brightness"))
        XCTAssertTrue(view.contains("Pulse duration / cycle"))
        XCTAssertTrue(view.contains("in: 0.0...5.0"))
        XCTAssertTrue(view.contains("Repeat cooldown"))
        XCTAssertTrue(view.contains("No speed-limit sign — disabled"))
    }

    func testV9010BLEDIMTransportBaselineIsRetained() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("private var bledimSequenceByID: [UUID: UInt8]"))
        XCTAssertTrue(monitor.contains("private func nextBLEDIMSequence(for id: UUID)"))
        XCTAssertTrue(monitor.contains("private func animationWriteInterval(for id: UUID) -> TimeInterval"))
        XCTAssertTrue(monitor.contains("0.05"))
        XCTAssertTrue(monitor.contains("protocolPacing=20Hz/rawBLEDIM"))
        XCTAssertFalse(monitor.contains("BLEDIM10Hz"))
        XCTAssertFalse(monitor.contains("let rounds = device.protocolKind == .bledim2 ? 3 : 1"))
    }

    func testOverspeedColorAndCooldown() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("var overspeedWarningColor: AmbientRGB"))
        XCTAssertTrue(monitor.contains("AmbientRGB(red: 255, green: 0, blue: 0)"))
        XCTAssertTrue(monitor.contains("overspeedWarningCooldownSeconds: TimeInterval = 60.0"))
        XCTAssertTrue(monitor.contains("Overspeed recross suppressed by 60s cooldown"))
        XCTAssertTrue(monitor.contains("let warningColor = overspeedWarningColor"))
    }
}
