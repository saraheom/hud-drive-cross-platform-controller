import XCTest
@testable import HUDController

final class V9030CrankAndHeadlightFreshSessionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testStartupStabilizesAfterHUDConnectBeforeStrictAllThreeCohort() throws {
        let monitor = try source("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("hudStartupStabilizationSeconds: TimeInterval = 5.0"))
        XCTAssertTrue(monitor.contains("HUD STARTUP stabilization armed"))
        XCTAssertTrue(monitor.contains("Task.sleep(for: .seconds(self.hudStartupStabilizationSeconds))"))
        XCTAssertTrue(monitor.contains("HUD STARTUP stabilization complete"))
        XCTAssertTrue(monitor.contains("HUD STARTUP FULL-COHORT common T0 ready=3 late=0"))
    }

    func testCenterOffRequiresFreshDashboardPhysicalSession() throws {
        let monitor = try source("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("armDashboardForFreshHeadlightCycle"))
        XCTAssertTrue(monitor.contains("minimumFreshHeadlightConnectionGenerationByID[dashboardID] = currentGeneration + 1"))
        XCTAssertTrue(monitor.contains("central.cancelPeripheralConnection(peripheral)"))
        XCTAssertTrue(monitor.contains("Fresh physical reconnect requirement satisfied"))
        XCTAssertTrue(monitor.contains("headlightStrictReadyTimeoutSeconds: TimeInterval = 15.0"))
    }

    func testPendingStrictMemberSurvivesDelayedDisconnectReconnect() throws {
        let monitor = try source("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("preserveStrictExpectedMembership"))
        XCTAssertTrue(monitor.contains("preserving expected membership for reconnect"))
        XCTAssertTrue(monitor.contains("Strict headlight cohort waiting for fresh physical reconnect"))
    }

    func testFreerideAndSpeedReliabilityRemainIntegrated() throws {
        let appState = try source("ios/HUDController/App/AppState.swift")
        let speed = try source("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(appState.contains("Restored original Freeride active mode via Navigation OFF after profile rehydration"))
        XCTAssertTrue(speed.contains("pending same-limit road confirmation"))
        XCTAssertTrue(speed.contains("rawFeatures="))
        XCTAssertTrue(speed.contains("URLQueryItem(name: \"distance\", value: \"650\")"))
    }
}
