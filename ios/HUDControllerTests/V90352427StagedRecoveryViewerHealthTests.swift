import XCTest

final class V90352427StagedRecoveryViewerHealthTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testCodecBadDataUsesBoundedGraceBeforeHardReset() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("CODEC_BAD_DATA_GRACE_ARMED"))
        XCTAssertTrue(video.contains("CODEC_BAD_DATA_GRACE_RECOVERED"))
        XCTAssertTrue(video.contains("CODEC_BAD_DATA_GRACE_EXHAUSTED"))
        XCTAssertTrue(video.contains("codecBadDataGraceAccessUnitBudget = 24"))
        XCTAssertTrue(video.contains("codecBadDataGraceTimeBudget: TimeInterval = 2.0"))
        XCTAssertTrue(video.contains("sustained codecBadDataErr (-8969) after bounded grace"))
        XCTAssertFalse(video.contains("consecutive codecBadDataErr (-8969) submissions\")"))
        XCTAssertFalse(video.contains("codecBadDataErr (-8969) output callback failures\")"))
    }

    func testReservedFirstFailureCaptureSkipsLifecycleAndContinuityWarnings() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        guard let start = video.range(of: "let isFirstFailureSignal ="),
              let end = video.range(of: "if isFirstFailureSignal", range: start.upperBound..<video.endIndex) else {
            return XCTFail("first-failure signal block not found")
        }
        let block = String(video[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(block.contains("codecBadDataErr"))
        XCTAssertTrue(block.contains("-8969"))
        XCTAssertFalse(block.contains("-12903"))
        XCTAssertFalse(block.contains("REFERENCE CONTINUITY WARNING"))
    }

    func testCurrentViewerHealthRequiresLiveSocketAndIsContinuouslyPolled() throws {
        let app = try source("HUDController/App/AppState.swift")
        XCTAssertTrue(app.contains("sessionScoped ? (established && clientSeen && liveFrameSent) : established"))
        XCTAssertTrue(app.contains("hudU2WReadySessionID"))
        XCTAssertTrue(app.contains("consecutiveViewerFailures >= 2"))
        XCTAssertTrue(app.contains("current HUD MJPEG viewer no longer established/session-ready"))
        XCTAssertTrue(app.contains("let relay = await self.u2wHUDRelayStatus()"))
    }
}
