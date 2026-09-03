import XCTest
@testable import HUDController

final class V44HUDSessionRehydrationTests: XCTestCase {
    func testSpeedSettingsHavePersistentKeys() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("HUD.Speed.enabled"))
        XCTAssertTrue(source.contains("HUD.Speed.toleranceMph"))
        XCTAssertTrue(source.contains("HUD.Speed.showLimit"))
        XCTAssertTrue(source.contains("rehydrateHUDState()"))
    }

    func testOBDHasSessionResetRetryLoop() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/HudOBDController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("hudSessionDidReset(reason:"))
        XCTAssertTrue(source.contains("startAutoConnectLoop(reason:"))
        XCTAssertTrue(source.contains("Connect attempt"))
        XCTAssertTrue(source.contains("connected = false"))
    }

    func testBluetoothDetectsFirmwareHelloAsSessionReset() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Bluetooth/HudBluetoothManager.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("body[0] == 3, body[1] == 5, body[2] == 0"))
        XCTAssertTrue(source.contains("onHUDSessionReset?()"))
        XCTAssertTrue(source.contains("onTransportDisconnected?()"))
    }

    func testCaptureRearmRequiresHealthyScreenCapture() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("func hudSessionDidReset(reason: String)"))
        XCTAssertTrue(source.contains("capture health has priority"))
        XCTAssertTrue(source.contains("guard isCaptureHealthy"))
        XCTAssertTrue(source.contains("HUD session ready while capture unhealthy"))
        XCTAssertTrue(source.contains("forceFreerideForCaptureLoss"))

        // A cached validated maneuver may only be re-sent after the health
        // guard has passed.
        guard let reset = source.range(of: "func hudSessionDidReset(reason: String)"),
              let health = source.range(
                of: "guard isCaptureHealthy",
                range: reset.lowerBound..<source.endIndex
              ),
              let rearm = source.range(
                of: "armNavigationIfNeeded()",
                range: reset.lowerBound..<source.endIndex
              )
        else {
            XCTFail("Expected capture-health rearm path not found")
            return
        }

        XCTAssertLessThan(health.lowerBound, rearm.lowerBound)
        XCTAssertTrue(source.contains("navigation.current = latestInstruction"))
        XCTAssertTrue(source.contains("navigation.sendCurrent(owner: .ocr)"))
    }

    func testAmbientUsesThreeWindowHysteresis() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("absenceConfirmationWindows = 3"))
        XCTAssertTrue(source.contains("missedWindows >= self.absenceConfirmationWindows"))
        XCTAssertTrue(source.contains("rehydrateHUDState()"))
    }
}
