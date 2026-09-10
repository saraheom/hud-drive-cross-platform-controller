import XCTest
@testable import HUDController

final class V903415SpeedMarkerProbeTimeWeatherBootTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testProbeCanSendOriginalStyleZeroWithoutChangingProductionPacket() throws {
        XCTAssertEqual(
            HudProtocol.hex(HudCommands.speedLimitProbe(limit: 0, tolerance: 0, style: 0)),
            "02 7D 7F 65 7D 7F 00 00 00 00 00 00 00 00 00 00 00 00 03"
        )
        XCTAssertEqual(
            HudProtocol.hex(HudCommands.speedLimit(limit: 25, tolerance: 0)),
            "02 7D 7F 65 7D 7F 00 00 00 19 00 00 00 00 00 00 00 01 03"
        )
    }

    func testTemporaryVehicleProbeIsExplicitlyDiagnosticOnly() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let ui = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(speed.contains("runOriginalAutomaticMarkerProbe"))
        XCTAssertTrue(speed.contains("speedLimitProbe(limit: 0, tolerance: 0, style: 0)"))
        XCTAssertTrue(speed.contains("live matcher state untouched"))
        XCTAssertTrue(ui.contains("SPEED MARKER PROBE — TEMPORARY"))
        XCTAssertTrue(ui.contains("Restore current HUD"))
    }

    func testTimeWeatherReassertFollowsDashboardProfiles() throws {
        let obd = try source("HUDController/Vehicle/HudOBDController.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(obd.contains("onDashboardProfileApplied"))
        XCTAssertTrue(app.contains("scheduleTimeWeatherPostDashboardReassert"))
        XCTAssertTrue(app.contains("Post-dashboard time/weather"))
        XCTAssertTrue(app.contains("Task.sleep(for: .milliseconds(300))"))
    }
}
