import XCTest
@testable import HUDController

final class V79ReleaseCompileRegressionTests: XCTestCase {
    func testRecoveryStateUsesExplicitSelfInsideStartCaptureClosure() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/ExternalNavigationCapture.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("self.lastFrameAt = Date()"))
        XCTAssertTrue(source.contains("self.recoveryAttempt = 0"))
        XCTAssertTrue(source.contains("self.recoveryInFlight = false"))
    }
}
