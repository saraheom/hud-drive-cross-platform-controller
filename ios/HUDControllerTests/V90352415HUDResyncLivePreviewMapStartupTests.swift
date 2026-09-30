import XCTest
@testable import HUDController

final class V90352415HUDResyncLivePreviewMapStartupTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testHUDRebootReassertsCurrentCarPlayPresentation() throws {
        let app = try source("HUDController/App/AppState.swift")
        let rgd = try source("HUDController/Navigation/RouteGuidanceAdapterClient.swift")
        XCTAssertTrue(app.contains(#"routeGuidance.reassertPhysicalHUD(reason: "HUD rehydrate phase 2 / \(reason)")"#))
        XCTAssertTrue(app.contains(#"routeGuidance.reassertPhysicalHUD(reason: "HUD rehydrate phase 3 / \(reason)")"#))
        XCTAssertTrue(rgd.contains("func reassertPhysicalHUD(reason: String)"))
        XCTAssertTrue(rgd.contains("navigation.reassertNavigationMode(owner: .carPlayAdapter, reason: reason, delayed: true)"))
        XCTAssertTrue(rgd.contains("navigation.sendCurrent(owner: .carPlayAdapter)"))
    }

    func testAppOnlyPreviewDoesNotEnterPhysicalMapMode() throws {
        let app = try source("HUDController/App/AppState.swift")
        let start = try XCTUnwrap(app.range(of: "func startMainVideoPreview()"))
        let stop = try XCTUnwrap(app.range(of: "func stopMainVideoPreview", range: start.upperBound..<app.endIndex))
        let block = String(app[start.lowerBound..<stop.lowerBound])
        XCTAssertTrue(block.contains(#"mainVideo.start(reason: "app-only live preview")"#))
        XCTAssertFalse(block.contains("HudCommands.kivicMode(6)"))
        XCTAssertFalse(block.contains("u2whud-start.cgi"))
    }

    func testMapModeStartupNoLongerFailsDuringTCPPreparing() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(app.contains("up to 12 s to establish TCP/receive first bytes"))
        XCTAssertTrue(app.contains("up to 20 s after transport readiness"))
        XCTAssertTrue(video.contains("TCP_PREPARING / TCP_WAITING /"))
        XCTAssertTrue(video.contains("authority for real failed/EOF states"))
    }

    func testNavigationModeAssuranceIsSparseAndCastingAware() throws {
        let nav = try source("HUDController/Navigation/HudNavigationController.swift")
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(nav.contains("minimumInterval: TimeInterval = 8.0"))
        XCTAssertTrue(nav.contains("physicalNavigationModeAllowed"))
        XCTAssertTrue(app.contains("return !self.hudU2WLiveRelayActive"))
    }
}
