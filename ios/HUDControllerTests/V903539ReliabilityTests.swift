import XCTest
@testable import HUDController

final class V903539ReliabilityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testRouteGuidanceTransportHoldoverDoesNotImmediatelyDropHUD() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        XCTAssertTrue(route.contains("transportFailureHoldoverInterval: TimeInterval = 45.0"))
        XCTAssertTrue(route.contains("CARPLAY RGD HOLD"))
        XCTAssertTrue(route.contains("Ignoring first inactive sample"))
        XCTAssertTrue(route.contains("confirmations < 2"))
    }

    func testMainVideoFreshnessWatchdogCanRecoverFrozenCrop() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("staleFrameInterval: TimeInterval = 10.0"))
        XCTAssertTrue(video.contains("U2W VIDEO WATCH"))
        XCTAssertTrue(video.contains("workerGeneration"))
        XCTAssertTrue(video.contains("self.workerGeneration == generation"))
    }

    func testAmbientReconnectRecoveryDoesNotReintroduceHeadlightPowerOnBlink() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("if becamePresent {"))
        XCTAssertFalse(monitor.contains("if becamePresent || !headlightPowerSessionActive"))
        XCTAssertTrue(monitor.contains("Manual Power OFF invalidated Already-On Minimal assumption"))
        XCTAssertFalse(monitor.contains("bledimExplicitPowerPrimeRequiredIDs.insert(dashboardID)"))
        XCTAssertTrue(monitor.contains("scheduleDashboardReconnectBrightnessRecovery"))
        XCTAssertTrue(monitor.contains("Fresh Dashboard reconnect held through boot settle; no Power ON/RGB write"))
        XCTAssertTrue(monitor.contains("Power ON/RGB intentionally omitted"))
    }

    func testRelayStatusUsesV815SessionMarkers() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("session_discovery_seen"))
        XCTAssertTrue(app.contains("session_client_seen"))
        XCTAssertTrue(app.contains("session_live_frame_sent"))
        XCTAssertTrue(app.contains("U2W v8.15"))
    }
}
