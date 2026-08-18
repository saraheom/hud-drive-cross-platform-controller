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

    func testManualStopClearsCaptureIntent() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        guard let stopStart = source.range(of: "func stop()"),
              let nextFunction = source.range(
                of: "\n    func ",
                range: stopStart.upperBound..<source.endIndex
              )
        else {
            XCTFail("Manual stop implementation not found")
            return
        }

        let stopBody = String(
            source[stopStart.lowerBound..<nextFunction.lowerBound]
        )

        XCTAssertTrue(stopBody.contains("captureDesired = false"))
        XCTAssertTrue(stopBody.contains("forceFreerideForCaptureLoss"))
    }

    func testOtherAppsDoNotClearUserArmedCaptureIntent() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        // The explicit inactive/unknown-screen path may force Freeride, but
        // capture intent remains armed. We validate the policy directly
        // instead of pinning this test to a private helper name.
        XCTAssertTrue(
            source.contains(
                "switching to Home Screen or another app does not clear"
            ) ||
            source.contains(
                "app switching / Maps inactivity must never clear it"
            )
        )

        guard let disconnectStart = source.range(
            of: "func hudTransportDisconnected(reason: String)"
        ),
        let healthStart = source.range(
            of: "private var isCaptureHealthy",
            range: disconnectStart.upperBound..<source.endIndex
        )
        else {
            XCTFail("HUD transport lifecycle implementation not found")
            return
        }

        let transportBody = String(
            source[disconnectStart.lowerBound..<healthStart.lowerBound]
        )

        // Even an actual HUD transport loss preserves the user's armed intent;
        // merely opening another app must therefore not clear it either.
        XCTAssertFalse(transportBody.contains("captureDesired = false"))
        XCTAssertTrue(transportBody.contains("preserving userArmed="))
    }
}
