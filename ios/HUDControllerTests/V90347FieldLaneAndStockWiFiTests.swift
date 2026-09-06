import XCTest
@testable import HUDController

final class V90347FieldLaneAndStockWiFiTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV88ResolvedLanePathDoesNotUseLegacyManeuverCache() throws {
        let app = try source("HUDController/App/AppState.swift")
        let a = try XCTUnwrap(app.range(of: "private func receiveResolvedV88LaneGuidance"))
        let b = try XCTUnwrap(app.range(of: "private func receiveLegacyV87LaneGuidance", range: a.upperBound..<app.endIndex))
        let block = String(app[a.lowerBound..<b.lowerBound])
        XCTAssertTrue(block.contains("state.laneGuidanceIndex"))
        XCTAssertTrue(block.contains("state.laneGuidanceEventIndex"))
        XCTAssertFalse(block.contains("liveLaneCacheByManeuver"))
    }

    func testManeuverRedrawGetsImmediateSameManeuverLaneReassert() throws {
        let route = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        let app = try source("HUDController/App/AppState.swift")
        let send = try XCTUnwrap(route.range(of: "navigation.sendCurrent(owner: .carPlayAdapter)"))
        let callback = try XCTUnwrap(route.range(of: "onManeuverDelivered?", range: send.upperBound..<route.endIndex))
        XCTAssertLessThan(send.lowerBound, callback.lowerBound)
        XCTAssertTrue(app.contains("reassertLiveLaneAfterManeuverDelivery"))
        XCTAssertTrue(app.contains("activeManeuver == maneuverIndex"))
        XCTAssertTrue(app.contains("Lane policy → post-maneuver reassert"))
    }

    func testPresentationSettingsResendManeuverBeforeLaneLayer() throws {
        let app = try source("HUDController/App/AppState.swift")
        let a = try XCTUnwrap(app.range(of: "func applyNavigationPresentationSettings"))
        let b = try XCTUnwrap(app.range(of: "private func shouldDisplayActiveLanes", range: a.upperBound..<app.endIndex))
        let block = String(app[a.lowerBound..<b.lowerBound])
        let maneuver = try XCTUnwrap(block.range(of: "navigation.sendCurrent"))
        let lanes = try XCTUnwrap(block.range(of: "reevaluateActiveLaneGuidance"))
        XCTAssertLessThan(maneuver.lowerBound, lanes.lowerBound)
    }

    func testWiFiBootstrapMatchesCapturedStockSequence() throws {
        let app = try source("HUDController/App/AppState.swift")
        let a = try XCTUnwrap(app.range(of: "func enableHUDWiFiExposure"))
        let b = try XCTUnwrap(app.range(of: "func holdHUDWiFiCastingModeForDiagnostics", range: a.upperBound..<app.endIndex))
        let block = String(app[a.lowerBound..<b.lowerBound])
        let hotspot = try XCTUnwrap(block.range(of: "hudHotspotBaseband(is5G: true, forceEnable: false)"))
        let mode5 = try XCTUnwrap(block.range(of: "HudCommands.kivicMode(5)"))
        XCTAssertLessThan(hotspot.lowerBound, mode5.lowerBound)
        XCTAssertTrue(block.contains(".milliseconds(5000)"))
        XCTAssertFalse(block.contains("HudCommands.kivicMode(4)"))
    }

    func testFailedAPPinExperimentIsRetiredAndNoOTAPacketIsUsed() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(app.contains("returnHUDRendererKeepingWiFi"))
        XCTAssertFalse(app.contains("hudHotspotBaseband(is5G: true, forceEnable: true)"))
        XCTAssertTrue(app.contains("startFirmwareMaintenance"))
        XCTAssertFalse(app.contains("HudCommands.softwareUpdate"))
    }
}
