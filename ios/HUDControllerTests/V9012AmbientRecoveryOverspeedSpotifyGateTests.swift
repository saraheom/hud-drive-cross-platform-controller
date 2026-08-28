import XCTest
@testable import HUDController

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

    func testRapidHeadlightEdgesInvalidateEntireOldBreathTimeline() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("cancelSynchronizedBreathForHeadlightEdge"))
        XCTAssertTrue(monitor.contains("authoritative headlight ON"))
        XCTAssertTrue(monitor.contains("authoritative headlight OFF"))
        XCTAssertTrue(monitor.contains("activeBreathIDs.removeAll()"))
        XCTAssertTrue(monitor.contains("breathPrepareTasks[doorID]?.cancel()"))
    }

    func testInterruptedBLEDIMTransientRestoresSteadyStateInsteadOfRejoiningBreath() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("interruptedTransientState"))
        XCTAssertTrue(monitor.contains("steadyStateRecoveryPendingIDs.insert(id)"))
        XCTAssertTrue(monitor.contains("headlightAnimatedEpochByID[id] = self.headlightPowerEpoch"))
        XCTAssertTrue(monitor.contains("Interrupted headlight Breath will restore steady state on reconnect"))
        XCTAssertTrue(monitor.contains("GATT ready with pending steady-state recovery"))
        XCTAssertTrue(monitor.contains("scheduleRobustSteadyStateRecovery"))
        XCTAssertFalse(monitor.contains("restartHeadlightBreathOnReconnectIDs"))
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
        XCTAssertTrue(warning.contains("overspeed restore safety reassert"))
        XCTAssertTrue(warning.contains("doorTargetBrightness(night: vehicleHeadlightsActive)"))
    }

    func testAsyncValidityHelpersRemainMainActorIsolated() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("@MainActor func requestStillValid() -> Bool"))
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

    func testBLEDIMAnimationRateAndFailSafeRecovery() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("pairedDevice(id)?.protocolKind == .bledim2 ? 0.10 : 0.05"))
        XCTAssertTrue(monitor.contains("let rounds = device.protocolKind == .bledim2 ? 3 : 1"))
        XCTAssertTrue(monitor.contains("post-breath safety"))
        XCTAssertTrue(monitor.contains("post-fade safety"))
        XCTAssertTrue(monitor.contains("Steady-state recovery complete"))
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
