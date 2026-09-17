import XCTest
@testable import HUDController

final class V9035132StabilizationTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testMainVideoPreservesLastKnownGoodDecoderAcrossLiveEdgeReseeds() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("decoderStaleFrameInterval: TimeInterval = 20.0"))
        XCTAssertTrue(video.contains("sourceStaleInterval: TimeInterval = 60.0"))
        XCTAssertTrue(video.contains("KEEP decoder session and continue validated P-frames"))
        XCTAssertTrue(video.contains("activeSPS"))
        XCTAssertTrue(video.contains("pendingSPS"))
        XCTAssertTrue(video.contains("preserving last-known-good decoder"))
        XCTAssertTrue(video.contains("prepareForStreamRestart"))
        XCTAssertTrue(video.contains("worker.reconnectAtLiveEdge"))
        XCTAssertTrue(video.contains("Atomic promotion: only now retire the prior VideoToolbox session."))
    }

    func testHUDViewerReadinessIsScopedToCurrentRelaySession() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("clientSeen && liveFrameSent"))
        XCTAssertTrue(app.contains("CURRENT SESSION READY"))
        XCTAssertTrue(app.contains("hudU2WAutomaticViewerRecoveryCount == 0"))
        XCTAssertTrue(app.contains("AUTO VIEWER RECOVERY mode4→mode6 only"))
        XCTAssertTrue(app.contains("preserving STA credentials"))
    }

    func testOBDDiagnosticTransferRequiresValidFramingAndExactChunks() throws {
        let bluetooth = try source("HUDController/Bluetooth/HudBluetoothManager.swift")
        XCTAssertTrue(bluetooth.contains("shouldSuppressDuplicateDiagnosticBLEFragment"))
        XCTAssertTrue(bluetooth.contains("captureOBDDiagnosticRawBLE(data)"))
        XCTAssertTrue(bluetooth.contains("available == chunkSize"))
        XCTAssertTrue(bluetooth.contains("Accepted returned diagnostic stream"))
        XCTAssertTrue(bluetooth.contains("LOG_CATEGORY_CRUSH"))
    }
}
