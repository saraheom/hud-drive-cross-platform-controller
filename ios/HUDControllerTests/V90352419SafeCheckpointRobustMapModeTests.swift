import XCTest
@testable import HUDController

final class V90352419SafeCheckpointRobustMapModeTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testV832LegacyHandshakeRemainsRecognizedWithoutOwningV834Runtime() throws {
        let video = try source("HUDController/MapMode/U2WMainVideoClient.swift")
        XCTAssertTrue(video.contains("Data(\"U2WH2649\".utf8)"))
        XCTAssertTrue(video.contains("boundedCheckpointRecovery = true"))
        XCTAssertTrue(video.contains("v8.32 safe-checkpoint recovery"))
        XCTAssertTrue(video.contains("checkpoint already attempted in this recovery episode; no reconnect loop"))
        XCTAssertTrue(video.contains("TCP relay handshake U2WH2649 accepted"))
        XCTAssertTrue(video.contains("v8.34 package uses exact v8.31 raw relay"))
        XCTAssertTrue(video.contains("mirror rotation is lossless/atomic"))
    }

    func testFalseType5IDRIsRejectedBeforeDecoder() throws {
        let sanitizer = try source("HUDController/MapMode/H264MainVideoSanitizer.swift")
        XCTAssertTrue(sanitizer.contains("let normalizedSliceType = info.sliceType >= 5 ? info.sliceType - 5 : info.sliceType"))
        XCTAssertTrue(sanitizer.contains("(normalizedSliceType == 2 || normalizedSliceType == 4), info.frameNum == 0"))
    }

    func testPhysicalMapModeDoesNotExitWhenMainVideoIsStale() throws {
        let app = try source("HUDController/App/AppState.swift")
        let start = try XCTUnwrap(app.range(of: "private func startHUDU2WDisplayHealthMonitor()"))
        let end = try XCTUnwrap(app.range(of: "private func failSafeHUDU2WDisplayToStock", range: start.upperBound..<app.endIndex))
        let block = String(app[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(block.contains("KEEPING physical mode 6 + JPEG relay active"))
        XCTAssertTrue(block.contains("fallback canvas"))
        XCTAssertFalse(block.contains("stopHUDU2WSTAHomeProbe()"))
        XCTAssertFalse(block.contains("HudCommands.kivicMode(4)"))
    }
}
