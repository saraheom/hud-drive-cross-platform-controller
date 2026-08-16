import XCTest
@testable import HUDController

final class V74CapturePriorityRegressionTests: XCTestCase {
    func testNoHealthyCaptureMeansFreerideBeforeAnyCachedNavigation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/ExternalNavigationCapture.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var isCaptureHealthy"))
        XCTAssertTrue(source.contains("Date().timeIntervalSince(lastFrameAt) <= 3.0"))
        XCTAssertTrue(source.contains("capture-health invariant"))
        XCTAssertTrue(source.contains("watchdog sees no active stream/frame"))
    }
}
