import XCTest
@testable import HUDController

final class V90352410IncrementalSourceAcquireTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV2410KeepsImmediateRenderingAndExistingEpochRecovery() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("self.latestFrame = image"))
        XCTAssertTrue(video.contains("self.transportPhase = \"LIVE\""))
        XCTAssertTrue(video.contains("preflightRequiredContinuity: TimeInterval = 300.0"))
        XCTAssertTrue(video.contains("codecBadDataErr (-8969) quarantined current H.264 epoch"))
        XCTAssertTrue(video.contains("v8.29-incremental-source-acquire+v8.28-relay-core"))
    }

    func testV2410OBDArchiveCollectionHasNoGPSGate() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("appVersion=v90.35.3.24.10"))
        XCTAssertTrue(app.contains("no GPS gate; v24.10 length/framing reconstruction active"))
        XCTAssertFalse(app.contains("guard speedEngine.currentSpeedMph <= 1 else"))
    }

    func testUIExplainsV829AndFiveMinuteMilestoneDoesNotGateRendering() throws {
        let ui = try source("HUDController/UI/NavigationHUDPreviewCard.swift")
        XCTAssertTrue(ui.contains("v90.35.3.24.10 pairs with U2W v8.29"))
        XCTAssertTrue(ui.contains("live map image should appear as soon as the first valid frame decodes"))
        XCTAssertTrue(ui.contains("only the extended stability milestone"))
    }
}
