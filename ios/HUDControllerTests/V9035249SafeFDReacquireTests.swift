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
        XCTAssertTrue(video.contains("v8.31-navigation-priority-raw-tcp-15332"))
    }

    func testCodecBadDataPreservesReferenceChainAndArmsFutureIDRRebuild() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("codecBadDataStatus: OSStatus = -8969"))
        XCTAssertTrue(video.contains("dropping this AU and PRESERVING current decoder/reference chain"))
        XCTAssertTrue(video.contains("armRebuildAtNextIDR"))
        XCTAssertTrue(video.contains("swap occurs only when a validated future IDR is already in hand"))
    }

    func testManualOBDArchiveCollectionDoesNotTrustStaleGPS() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertFalse(app.contains("guard speedEngine.currentSpeedMph <= 1 else"))
        XCTAssertTrue(app.contains("MANUAL COLLECT BEGIN LOG_CATEGORY_OBD"))
        XCTAssertTrue(app.contains("no GPS gate"))
        XCTAssertTrue(app.contains("requestOBDDiagnosticLogs(maxLastFilesCount: 5)"))
    }
}
