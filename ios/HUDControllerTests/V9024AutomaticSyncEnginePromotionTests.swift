import XCTest
@testable import HUDController

final class V9024AutomaticSyncEnginePromotionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testCourtesyConnectionsCannotAnimateBeforeHUDTransport() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("guard hudEnginePowerSignalPresent else"))
        XCTAssertTrue(monitor.contains("Automatic Breath held until HUD connection"))
        XCTAssertTrue(monitor.contains("Courtesy/headlight ON while HUD disconnected; animation intentionally held"))
    }

    func testHUDTransportOwnsAmbientStartupAndOBDIsDiagnosticOnly() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("scheduleEngineStartupSynchronization(source: \"HUD connected\")"))
        XCTAssertTrue(monitor.contains("HUD transport readiness is the automatic-animation session edge"))
        XCTAssertTrue(monitor.contains("OBD remains diagnostic/corroborating state only"))
    }

    func testHUDStartupRequiresAllThreeAndHasNoPartialFallback() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("engineStartupMaxWaitSeconds: TimeInterval = 10.0"))
        XCTAssertTrue(monitor.contains("requiredRoles: Set<AmbientLightRole> = [.centerConsole, .door, .dashboard]"))
        XCTAssertTrue(monitor.contains("HUD STARTUP FULL-COHORT opened"))
        XCTAssertTrue(monitor.contains("HUD STARTUP FULL-COHORT common T0 ready=3 late=0"))
        XCTAssertTrue(monitor.contains("strict all-three readiness not met"))
        XCTAssertTrue(monitor.contains("no partial/late Breath"))
    }

    func testUIExplainsHUDStartupAndLaterHeadlightRule() throws {
        let view = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(view.contains("Automatic Breath is HUD-connection-gated"))
        XCTAssertTrue(view.contains("Center + Door + Dashboard"))
        XCTAssertTrue(view.contains("Door is already on and Center + Dashboard turn on with the headlights"))
        XCTAssertTrue(view.contains("There is no late independent catch-up Breath"))
    }
}
