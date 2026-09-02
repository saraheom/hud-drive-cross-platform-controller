import XCTest
@testable import HUDController

final class V9024AutomaticSyncEnginePromotionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testCourtesyConnectionsCannotAnimateBeforeOBD() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("guard obdEnginePowerSignalPresent else"))
        XCTAssertTrue(monitor.contains("Automatic Breath held until OBD connection"))
        XCTAssertTrue(monitor.contains("Courtesy/headlight ON while OBD disconnected; animation intentionally held"))
    }

    func testHUDTransportNoLongerOwnsAmbientStartup() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("HUD transport remains available for engine diagnostics"))
        XCTAssertTrue(monitor.contains("it no longer arms ambient animation"))
        XCTAssertTrue(monitor.contains("scheduleEngineStartupSynchronization(source: \"OBD connected\")"))
    }

    func testOBDStartupRequiresAllThreeAndHasNoPartialFallback() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("engineStartupMaxWaitSeconds: TimeInterval = 10.0"))
        XCTAssertTrue(monitor.contains("requiredRoles: Set<AmbientLightRole> = [.centerConsole, .door, .dashboard]"))
        XCTAssertTrue(monitor.contains("OBD STARTUP FULL-COHORT opened"))
        XCTAssertTrue(monitor.contains("OBD STARTUP FULL-COHORT common T0 ready=3 late=0"))
        XCTAssertTrue(monitor.contains("strict all-three readiness not met"))
        XCTAssertTrue(monitor.contains("no partial/late Breath"))
    }

    func testUIExplainsOBDStartupAndLaterHeadlightRule() throws {
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(view.contains("Automatic Breath is OBD-gated"))
        XCTAssertTrue(view.contains("Center + Door + Dashboard"))
        XCTAssertTrue(view.contains("Door is already on and Center + Dashboard turn on with the headlights"))
        XCTAssertTrue(view.contains("There is no late independent catch-up Breath"))
    }
}
