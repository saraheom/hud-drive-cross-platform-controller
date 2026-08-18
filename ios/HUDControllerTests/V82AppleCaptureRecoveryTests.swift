import XCTest
@testable import HUDController

final class V82AppleCaptureRecoveryTests: XCTestCase {
    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/ExternalNavigationCapture.swift"
            ),
            encoding: .utf8
        )
    }

    func testHealthUsesActualRawFrameAndFourSecondSoftBoundary() throws {
        let source = try source()
        XCTAssertTrue(
            source.contains("Date().timeIntervalSince(lastFrameAt) <= 4.0")
        )
        XCTAssertFalse(
            source.contains("self.lastFrameAt = Date()\n                    self.recoveryAttempt")
        )
    }

    func testWatchdogDoesNotTearDownAtThreeSeconds() throws {
        let source = try source()
        XCTAssertTrue(source.contains("if age > 4"))
        XCTAssertTrue(source.contains("if age > 8"))
        XCTAssertFalse(source.contains("if age > 3"))
    }

    func testZombieReplacementStreamHasFirstFrameDeadline() throws {
        let source = try source()
        XCTAssertTrue(source.contains("private var streamCreatedAt"))
        XCTAssertTrue(source.contains("if self.lastFrameAt == nil"))
        XCTAssertTrue(source.contains("if startupAge > 8"))
        XCTAssertTrue(source.contains("discarding zombie stream"))
        XCTAssertTrue(source.contains("no first raw frame within 8s"))
    }

    func testRawFrameMarksStreamHealthy() throws {
        let source = try source()
        XCTAssertTrue(source.contains("First raw frame received; stream is healthy"))
        XCTAssertTrue(source.contains("self.streamCreatedAt = nil"))
        XCTAssertTrue(source.contains("self.lastFrameAt = Date()"))
    }
}
