import XCTest
@testable import HUDController

final class V90352410IncrementalSourceAcquireTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV2410HistoryRemainsDocumentedWhileCurrentRuntimeUsesSafeBaseline() throws {
        let old = try source("../V90_35_3_24_10_RELEASE.md")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(old.contains("U2W v8.29"))
        XCTAssertTrue(video.contains("self.latestFrame = image"))
        XCTAssertTrue(video.contains("self.transportPhase = \"LIVE\""))
        XCTAssertTrue(video.contains("preflightRequiredContinuity: TimeInterval = 300.0"))
        XCTAssertTrue(video.contains("v8.27.1-passive-diagnostic-tcp-15332"))
    }

    func testV2411OBDArchiveCollectionHasNoGPSGate() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.11"))
        XCTAssertTrue(app.contains("no GPS gate; v24.10 length/framing reconstruction retained"))
        XCTAssertFalse(app.contains("guard speedEngine.currentSpeedMph <= 1 else"))
    }

    func testV2411KeepsMainVideoOffOutsideExplicitLiveMapMode() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(app.contains("app launch — early U2W car-session predecode"))
        XCTAssertFalse(app.contains("HUD BLE transport ready — reassert continuous predecode"))
        XCTAssertTrue(app.contains("live U2W Map Mode relay"))
        XCTAssertTrue(app.contains("passive diagnostic commute mode"))
    }

    func testV2411PassiveProbeEndpointsAndUI() throws {
        let diagnostic = try source("HUDController/MapMode/U2WMainVideoDiagnosticClient.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(diagnostic.contains("u2wvideo-diag-start.cgi"))
        XCTAssertTrue(diagnostic.contains("u2wvideo-diag-mark.cgi"))
        XCTAssertTrue(diagnostic.contains("u2wvideo-diag-bundle.cgi"))
        XCTAssertTrue(ui.contains("Collect U2W MainVideo diagnostic bundle"))
        XCTAssertTrue(ui.contains("does not enable Map Mode"))
    }
}
