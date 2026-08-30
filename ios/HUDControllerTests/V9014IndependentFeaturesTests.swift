import XCTest
@testable import HUDController

final class V9014IndependentFeaturesTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testConfigurableOverspeedWarningRemains() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let view = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(monitor.contains("let threshold = speedLimitMph + offset"))
        XCTAssertTrue(monitor.contains("AmbientRGB(red: 255, green: 0, blue: 0)"))
        XCTAssertTrue(monitor.contains("overspeedWarningCooldownSeconds: TimeInterval = 60.0"))
        XCTAssertTrue(monitor.contains("max(0.0, min(5.0, overspeedWarningPulseDurationSeconds))"))
        XCTAssertTrue(view.contains("AMBIENT OVERSPEED WARNING"))
        XCTAssertTrue(view.contains("Warning color"))
        XCTAssertTrue(view.contains("Repeat cooldown"))
    }

    func testSpotifyVehicleGateAndOSMSourcesRemain() throws {
        let app = try source("HUDController/App/AppState.swift")
        let spotify = try source("HUDController/Media/SpotifyMediaController.swift")
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(spotify.contains("guard automaticVehicleWakeAllowed else"))
        XCTAssertTrue(app.contains("bluetooth.state == .connected || obd.connected"))
        XCTAssertTrue(speed.contains("case traceOSM = \"OSM Trace\""))
        XCTAssertTrue(speed.contains("case improvedTracePhilly = \"Improved + Philly GIS\""))
    }
}
