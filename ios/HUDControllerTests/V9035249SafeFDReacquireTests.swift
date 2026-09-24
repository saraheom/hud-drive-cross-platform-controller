import XCTest
@testable import HUDController

final class V9035249SafeFDReacquireTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV828HandshakeAndFiveMinuteContinuityTarget() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("Data(\"U2WH2646\".utf8)"))
        XCTAssertTrue(video.contains("preflightRequiredContinuity: TimeInterval = 300.0"))
        XCTAssertTrue(video.contains("LIVE • 5m continuity verified"))
        XCTAssertTrue(video.contains("v8.28-safe-fd-reacquire"))
    }

    func testCodecBadDataForcesFreshCodecEpochWithoutTCPReconnect() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("codecBadDataStatus: OSStatus = -8969"))
        XCTAssertTrue(video.contains("hardRecoverAwaitingFreshCodecEpoch"))
        XCTAssertTrue(video.contains("sanitizer.reset(clearParameterSets: true)"))
        XCTAssertTrue(video.contains("TCP PRESERVED; decoder + sanitizer parameter sets cleared"))
        XCTAssertTrue(video.contains("activeSPS = nil"))
        XCTAssertTrue(video.contains("activePPS = nil"))
    }

    func testManualOBDArchiveCollectionDoesNotTrustStaleGPS() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(app.contains("guard speedEngine.currentSpeedMph <= 1 else"))
        XCTAssertTrue(app.contains("MANUAL COLLECT BEGIN LOG_CATEGORY_OBD"))
        XCTAssertTrue(app.contains("no GPS gate"))
        XCTAssertTrue(app.contains("requestOBDDiagnosticLogs(maxLastFilesCount: 5)"))
    }
}
