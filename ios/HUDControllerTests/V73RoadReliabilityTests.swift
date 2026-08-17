import XCTest
@testable import HUDController

final class V73RoadReliabilityTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    func testCaptureHealthPrecedesCachedNavigationRearm() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )
        guard let reset = source.range(of: "func hudSessionDidReset"),
              let health = source.range(
                of: "guard isCaptureHealthy",
                range: reset.lowerBound..<source.endIndex
              ),
              let arm = source.range(
                of: "armNavigationIfNeeded()",
                range: reset.lowerBound..<source.endIndex
              )
        else {
            XCTFail("capture invariant not found")
            return
        }
        XCTAssertLessThan(health.lowerBound, arm.lowerBound)
        XCTAssertTrue(source.contains("Date().timeIntervalSince(lastFrameAt) <= 3.0"))
        XCTAssertTrue(source.contains("watchdog sees no active stream"))
    }

    func testSpeedMatcherUsesOriginalHudwayGeometryAndThresholds() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )
        XCTAssertTrue(source.contains("distanceMeters: 30"))
        XCTAssertTrue(source.contains("angle < 45 ? angle / 45 : 2"))
        XCTAssertTrue(source.contains("distance < 15 ? distance / 15 : 2"))
        XCTAssertTrue(source.contains("originalPolygonContains"))
        XCTAssertFalse(source.contains("reverseDelta"))
        XCTAssertFalse(source.contains("if distance > 45"))
    }

    func testGoogleMergeMapsToStraight() throws {
        let source = try source(
            "HUDController/Navigation/GoogleMapsOCRParser.swift"
        )
        XCTAssertTrue(
            source.contains("if s.contains(\"merge\") { return .straight }")
        )
    }

    func testAmbientUsesHybridScanAndConnectionStallRecovery() throws {
        let source = try source(
            "HUDController/Vehicle/AmbientLightMonitor.swift"
        )
        XCTAssertTrue(source.contains("Persistent connection stuck >6s"))
        XCTAssertTrue(source.contains("Ambient watchdog reassert"))
        XCTAssertTrue(source.contains("hybrid discovery remains armed"))
    }
}
