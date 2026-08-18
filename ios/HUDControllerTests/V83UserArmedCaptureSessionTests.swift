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
        XCTAssertTrue(
            stopBody.contains(
                "deactivateNavigation(reason: \"Screen capture manually stopped\")"
            )
        )
    }

    func testOnlyManualStopClearsIntentInPhysicalImplementation() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        // The file contains a physical-device implementation followed by a
        // simulator fallback. Scope this assertion only to the physical side.
        guard let simulatorBoundary = source.range(of: "#else") else {
            XCTFail("Simulator conditional boundary not found")
            return
        }

        let physicalSource = String(
            source[..<simulatorBoundary.lowerBound]
        )

        let assignments = physicalSource.components(
            separatedBy: "captureDesired = false"
        ).count - 1

        XCTAssertEqual(assignments, 1)

        guard let stopStart = physicalSource.range(of: "func stop()"),
              let nextFunction = physicalSource.range(
                of: "\n    func ",
                range: stopStart.upperBound..<physicalSource.endIndex
              )
        else {
            XCTFail("Physical manual stop implementation not found")
            return
        }

        let stopBody = String(
            physicalSource[stopStart.lowerBound..<nextFunction.lowerBound]
        )

        XCTAssertTrue(stopBody.contains("captureDesired = false"))
    }
}
