import XCTest
@testable import HUDController

final class V47DriveReliabilityTests: XCTestCase {
    func testSpeedNotificationUsesKmhProtocolInput() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("protocolSpeedKmh"))
        XCTAssertTrue(source.contains("speedMS * 3.6"))
        XCTAssertTrue(source.contains("HudCommands.speedNotification(kmh: protocolSpeedKmh)"))
    }

    func testCircularSpeedLimitPathRemoved() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Protocol/HudCommands.swift")
        let source = try String(contentsOf: url)
        XCTAssertFalse(source.contains("squareStyle: Bool"))
        XCTAssertTrue(source.contains("Never transmit the circular-style flag"))
        XCTAssertTrue(source.contains("payload.append(HudProtocol.int32(1))"))
    }

    func testHUDRehydrationHasThreePhases() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/App/AppState.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("PHASE 1 base"))
        XCTAssertTrue(source.contains("PHASE 2 persisted state"))
        XCTAssertTrue(source.contains("PHASE 3 display reassert"))
        XCTAssertTrue(source.contains("applyTimeWeather()"))
    }

    func testCaptureDesiredPersistsAndUnexpectedStopRecovers() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("HUD.Capture.desired"))
        XCTAssertTrue(source.contains("requestAutomaticStartIfDesired()"))
        XCTAssertTrue(source.contains("preserving navigation state during recovery"))
        XCTAssertTrue(source.contains("scheduleRecovery(reason: error.localizedDescription)"))
    }

    func testAmbientHybridReconnect() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("Hybrid recovery"))
        XCTAssertTrue(source.contains("self.startScanning()"))
        XCTAssertTrue(source.contains("self.scheduleConnectionRetry()"))
    }

    func testOBDHealthLoopReassertsConnection() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/HudOBDController.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("OBD HEALTH"))
        XCTAssertTrue(source.contains("OBD health keep-connected"))
        XCTAssertTrue(source.contains("startHealthLoop()"))
    }
}
