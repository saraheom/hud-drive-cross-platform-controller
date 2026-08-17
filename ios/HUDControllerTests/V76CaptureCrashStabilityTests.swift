import XCTest
@testable import HUDController

final class V76CaptureCrashStabilityTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    func testCaptureRecoveryIsSerialized() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("private var recoveryInFlight"))
        XCTAssertTrue(source.contains("guard !recoveryInFlight else"))
        XCTAssertTrue(source.contains("Recovery already in flight; coalescing"))
        XCTAssertTrue(source.contains("serialized recovery attempt="))
    }

    func testNewStreamDoesNotReuseOldFrameTimestamp() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("self.lastFrameAt = nil"))
        XCTAssertTrue(source.contains("guard let lastFrameAt = self.lastFrameAt else"))
    }

    func testSuccessfulFrameResetsRecoveryBackoff() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("lastFrameAt = Date()"))
        XCTAssertTrue(source.contains("recoveryAttempt = 0"))
        XCTAssertTrue(source.contains("recoveryInFlight = false"))
    }

    func testAmbientScanIsIdempotent() throws {
        let source = try source(
            "HUDController/Vehicle/AmbientLightMonitor.swift"
        )

        XCTAssertTrue(source.contains("private var isScanning"))
        XCTAssertTrue(source.contains("guard !isScanning else { return }"))
        XCTAssertTrue(source.contains("Started BLE advertisement scan for BLEDOM"))
    }
}
