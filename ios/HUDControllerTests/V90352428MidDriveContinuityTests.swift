import XCTest

final class V90352428MidDriveContinuityTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testGeneralizedContinuityQuarantineFeedsProductionPath() throws {
        let san = try source("HUDController/MapMode/H264MainVideoSanitizer.swift")
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(san.contains("func processBatch(_ nal: Data) -> [H264SanitizedNAL]"))
        XCTAssertTrue(san.contains("grossContinuityDistanceThreshold: UInt32 = 8"))
        XCTAssertTrue(san.contains("old_cadence_resumed"))
        XCTAssertTrue(video.contains("sanitizer.processBatch(nal)"))
        XCTAssertTrue(video.contains("AU_CONTINUITY_QUARANTINE"))
    }

    func testLifecyclePreservesDecoderAndReferenceChain() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        guard let start = video.range(of: "func suspendDecoderForLifecycle"),
              let end = video.range(of: "func reconnectAtLiveEdge", range: start.upperBound..<video.endIndex) else {
            return XCTFail("lifecycle block not found")
        }
        let block = String(video[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(block.contains("VideoToolbox + reference chain PRESERVED"))
        XCTAssertTrue(block.contains("no decoder rebuild, no sanitizer quarantine, no fresh-IDR requirement"))
        XCTAssertFalse(block.contains("hardRecoverAwaitingIDR"))
        XCTAssertFalse(block.contains("quarantineReferenceChainUntilIDR"))
    }

    func testGenericRecoveryCannotConsumeReservedCorruptionWindow() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        guard let start = video.range(of: "worker.onDecoderRecovery"),
              let end = video.range(of: "worker.onKeyframeRequestNeeded", range: start.upperBound..<video.endIndex) else {
            return XCTFail("decoder callback block not found")
        }
        let block = String(video[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(block.contains("triggerFirstFailureEvidence"))
    }
}
