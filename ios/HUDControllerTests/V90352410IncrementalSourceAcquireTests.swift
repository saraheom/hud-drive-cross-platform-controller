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
        XCTAssertTrue(video.contains("v8.34-hard-bounded-mirror-v831-raw-tcp-15332"))
    }

    func testV2411OBDArchiveCollectionHasNoGPSGate() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.29"))
        XCTAssertTrue(app.contains("no GPS gate; v24.10 length/framing reconstruction retained"))
        XCTAssertFalse(app.contains("guard speedEngine.currentSpeedMph <= 1 else"))
    }

    func testV2414NavigationPriorityKeepsMainVideoOffOutsideMapMode() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(app.contains("app session early predecode"))
        XCTAssertFalse(app.contains("HUD BLE transport ready — early predecode"))
        XCTAssertTrue(app.contains(#"mainVideo.start(reason: "app-only live preview")"#))
        XCTAssertTrue(app.contains(#"self.mainVideo.start(reason: "physical Map Mode live source (optional)")"#))
        XCTAssertTrue(app.contains("MainVideo remains idle"))
    }

    func testV2412AutomaticCodecProbeEndpointsAndUI() throws {
        let diagnostic = try source("HUDController/MapMode/U2WMainVideoDiagnosticClient.swift")
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(diagnostic.contains("u2wvideo-diag-start.cgi"))
        XCTAssertTrue(diagnostic.contains("u2wvideo-diag-bundle.cgi"))
        // v24.28 keeps the diagnostic endpoints underneath but retires the old probe-specific UI.
        XCTAssertTrue(ui.contains("Collect Live Map Diagnostic ZIP (parked)"))
        XCTAssertTrue(ui.contains("Detailed MainVideo, decoder, adapter-seam, and OBD ownership telemetry remains in the diagnostic ZIP"))
        XCTAssertFalse(ui.contains("Collect passive codec diagnostic bundle"))
        XCTAssertFalse(ui.contains("passive v8.27.2 source/topology observer"))
    }
}
