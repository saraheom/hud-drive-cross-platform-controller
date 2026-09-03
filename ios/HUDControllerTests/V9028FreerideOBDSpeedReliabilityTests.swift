import XCTest
@testable import HUDController

final class V9028FreerideOBDSpeedReliabilityTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV9029RestoresValidatedOBDBackoffBecauseOBDNoLongerGatesAnimation() throws {
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        XCTAssertTrue(obd.contains("case 1: retryDelay = 4.0"))
        XCTAssertTrue(obd.contains("default: retryDelay = 30.0"))
        XCTAssertFalse(obd.contains("transportReacquireGraceSeconds"))
    }

    func testFreerideUsesOriginalTypeZeroSimpleCenterAndExplicitModeRestore() throws {
        let app = try source("HUDController/App/AppState.swift")
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        let dashboard = try source("HUDController/UI/DashboardView.swift")
        XCTAssertTrue(obd.contains("center: \"Simple\""))
        XCTAssertFalse(app.contains("20s display watchdog"))
        XCTAssertFalse(app.contains("freerideWatchdogTask"))
        XCTAssertTrue(app.contains("Restore dashboard mode → Freeride (Navigation OFF)"))
        XCTAssertTrue(app.contains("HudCommands.navigationState(false)"))
        XCTAssertFalse(dashboard.contains("Toggle(\"Minimize widgets\""))
    }

    func testPendingSameDisplayedLimitIsDisplayOnlyContinuity() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("pending same-limit source confirmation"))
        XCTAssertTrue(speed.contains("pending same displayed limit"))
        XCTAssertTrue(speed.contains("Pending same-limit confirmation — disable native warning threshold"))
        XCTAssertTrue(speed.contains("improvedLastResolutionWarningEligible = false"))
    }

    func testPhiladelphiaUsesPointDistanceQueryWithRawDiagnostics() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("geometryType\", value: \"esriGeometryPoint\""))
        XCTAssertTrue(speed.contains("URLQueryItem(name: \"distance\", value: \"650\")"))
        XCTAssertTrue(speed.contains("URLQueryItem(name: \"units\", value: \"esriSRUnit_Meter\")"))
        XCTAssertTrue(speed.contains("pointRadius=650m rawFeatures=%d"))
    }
}
