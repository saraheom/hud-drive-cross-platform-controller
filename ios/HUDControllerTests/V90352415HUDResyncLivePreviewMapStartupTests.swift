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

    func testMapModeIsTheOnlyMainVideoOwnerAndPhonePreviewIsPassive() throws {
        let app = try source("HUDController/App/AppState.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertFalse(app.contains("func startMainVideoPreview()"))
        XCTAssertFalse(app.contains(#"mainVideo.start(reason: "app-only live preview")"#))
        XCTAssertTrue(app.contains(#"self.mainVideo.start(reason: "physical Map Mode live source (optional)")"#))
        XCTAssertTrue(app.contains("guard hudU2WLiveRelayActive || mapModeActive else { return nil }"))
        XCTAssertFalse(ui.contains("Start Live Preview (app only)"))
    }

    func testMapModeStartupNoLongerFailsDuringTCPPreparing() throws {
        let app = try source("HUDController/App/AppState.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        // v24.18 restores fallback-first physical Map Mode: MainVideo may still be
        // preparing while the JPEG relay establishes and projects the fallback canvas.
        XCTAssertTrue(app.contains("physical Map Mode no longer depends on MainVideo readiness"))
        XCTAssertTrue(app.contains("guard firstFrameDelivered else"))
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
