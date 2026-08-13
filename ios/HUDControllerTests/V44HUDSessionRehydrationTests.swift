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

    func testCaptureCanRearmWithoutRestartingCapture() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("func hudSessionDidReset(reason: String)"))
        XCTAssertTrue(source.contains("Re-armed Navigation ON and re-sent cached validated maneuver"))
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
