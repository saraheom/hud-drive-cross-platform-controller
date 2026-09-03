import XCTest
@testable import HUDController

final class V9029HUDGateOriginalFreerideTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHUDTransportIsAutomaticAnimationGateAndOBDIsDiagnosticOnly() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("scheduleEngineStartupSynchronization(source: \"HUD connected\")"))
        XCTAssertTrue(monitor.contains("Pending automatic sync cancelled because HUD disconnected"))
        XCTAssertTrue(monitor.contains("OBD remains diagnostic/corroborating state only"))
        XCTAssertTrue(monitor.contains("hudAnimationGate=1"))
        XCTAssertTrue(monitor.contains("startupSync=HUD-gated-all-three"))
    }

    func testStrictStartupAndLaterHeadlightCohortsRemainSynchronized() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("HUD STARTUP FULL-COHORT common T0 ready=3 late=0"))
        XCTAssertTrue(monitor.contains("strict all-three readiness not met"))
        XCTAssertTrue(monitor.contains("Door is enrolled only when Door itself is newly joining"))
        XCTAssertTrue(monitor.contains("HEADLIGHT STRICT-COHORT common T0"))
        XCTAssertTrue(monitor.contains("no partial/late Breath"))
    }

    func testOriginalFreerideProfileIsFollowedByExplicitActiveModeRestore() throws {
        let app = try source("HUDController/App/AppState.swift")
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        XCTAssertTrue(obd.contains("center: \"Simple\""))
        XCTAssertTrue(obd.contains("navigationLayout: false"))
        XCTAssertTrue(obd.contains("center: \"Navigation\""))
        XCTAssertTrue(obd.contains("navigationLayout: true"))
        XCTAssertTrue(app.contains("Restore dashboard mode → Freeride (Navigation OFF)"))
        XCTAssertTrue(app.contains("HudCommands.navigationState(false)"))
        XCTAssertTrue(app.contains("Restore dashboard mode → Navigation ON"))
        XCTAssertFalse(app.contains("20s display watchdog"))
        XCTAssertFalse(app.contains("freerideWatchdogTask"))
    }

    func testSpeedNoBlinkAndPhiladelphiaPointQueryAreRetained() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("pending same-limit source confirmation"))
        XCTAssertTrue(speed.contains("Pending same-limit confirmation — disable native warning threshold"))
        XCTAssertTrue(speed.contains("geometryType\", value: \"esriGeometryPoint\""))
        XCTAssertTrue(speed.contains("URLQueryItem(name: \"distance\", value: \"650\")"))
        XCTAssertTrue(speed.contains("pointRadius=650m rawFeatures=%d"))
    }
}
