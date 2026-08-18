import XCTest
@testable import HUDController

final class V84SimulatorCaptureInterfaceTests: XCTestCase {
    func testSimulatorFallbackExposesHudTransportLifecycleAPI() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/ExternalNavigationCapture.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("func hudTransportReady(reason: String)"))
        XCTAssertTrue(source.contains("func hudTransportDisconnected(reason: String)"))
    }

    func testSimulatorFallbackDefaultsCaptureIntentOff() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/ExternalNavigationCapture.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private(set) var captureDesired = false"))
    }
}
