import XCTest
@testable import HUDController

final class V83UserArmedCaptureSessionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testFreshInstallCaptureDefaultsOff() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(
            source.contains(
                "self.captureDesired = d.object(forKey: \"HUD.Capture.desired\") == nil"
            )
        )
        XCTAssertTrue(source.contains("? false : d.bool"))
    }

    func testManualStartRequiresConnectedHUDAndArmsIntent() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(
            source.contains(
                "guard navigation.bluetooth.state == .connected else"
            )
        )
        XCTAssertTrue(source.contains("captureDesired = true"))
        XCTAssertTrue(
            source.contains("Connect HUD before starting capture")
        )
    }

    func testAutomaticRecoveryRequiresUserIntentAndHudConnection() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("guard captureDesired,"))
        XCTAssertTrue(
            source.contains(
                "navigation.bluetooth.state == .connected,"
            )
        )
    }

    func testHudDisconnectPreservesUserIntentButStopsTransport() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        guard let start = source.range(
            of: "func hudTransportDisconnected(reason: String)"
        ),
        let end = source.range(
            of: "private var isCaptureHealthy",
            range: start.upperBound..<source.endIndex
        ) else {
            XCTFail("HUD disconnect policy not found")
            return
        }

        let body = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("activeStream.stopCapture"))
        XCTAssertTrue(body.contains("preserving userArmed="))
        XCTAssertFalse(body.contains("captureDesired = false"))
    }

    func testOnlyManualStopClearsCaptureIntent() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        let assignments = source.components(
            separatedBy: "captureDesired = false"
        ).count - 1

        XCTAssertEqual(assignments, 1)
        XCTAssertTrue(source.contains("func stop()"))
    }

    func testOtherAppsOnlyDeactivateNavigationNotCapture() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        // Inactive/unknown OCR paths are allowed to send Freeride, but must
        // not clear the user's capture intent.
        guard let start = source.range(of: "private func apply("),
              let end = source.range(
                of: "private func compactStreetName",
                range: start.upperBound..<source.endIndex
              )
        else {
            XCTFail("OCR apply lifecycle not found")
            return
        }

        let body = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(body.contains("captureDesired = false"))
        XCTAssertFalse(body.contains("stopCapture"))
    }
}
