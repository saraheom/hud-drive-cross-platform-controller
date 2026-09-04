import XCTest
@testable import HUDController

final class V9033FieldRefinementTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testApplePreRoadRouteStateSixGetsLongerFreshnessWithoutChangingNormalTimeout() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        XCTAssertTrue(route.contains("staleInterval: TimeInterval = 4.5"))
        XCTAssertTrue(route.contains("preRoadStartupStaleInterval: TimeInterval = 20.0"))
        XCTAssertTrue(route.contains("snapshot.active && snapshot.routeState == 6"))
        XCTAssertTrue(route.contains("lastSequenceProgressAtBySource"))
        XCTAssertTrue(route.contains("CARPLAY RGD STARTUP"))
    }

    func testCarPlaySpeedAssistCannotOverrideContradictoryGeometry() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("match.currentDistance <= 40, match.currentAngle <= 45"))
        XCTAssertTrue(speed.contains("match.currentDistance <= 50, match.currentAngle <= 70"))
        XCTAssertTrue(speed.contains("rgdCurrent="))
        XCTAssertTrue(speed.contains("martin luther king junior"))
    }

    func testOverspeedWarningSeparatesDayNightBrightnessAndSmoothlyRestores() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let view = try source("HUDController/UI/VehicleView.swift")
        XCTAssertTrue(monitor.contains("overspeedWarningNightBrightness"))
        XCTAssertTrue(monitor.contains("warningIsNight = headlightPowerSessionActive"))
        XCTAssertTrue(monitor.contains("interpolatedOverspeedColor"))
        XCTAssertTrue(monitor.contains("overspeedRestoreTransitionSeconds: TimeInterval = 1.0"))
        XCTAssertTrue(monitor.contains("overspeed smooth RGB restore"))
        XCTAssertTrue(monitor.contains("overspeed smooth brightness restore"))
        XCTAssertTrue(view.contains("Day warning brightness"))
        XCTAssertTrue(view.contains("Night warning brightness"))
    }
}
