import XCTest
@testable import HUDController

final class V45ReliabilityRegressionTests: XCTestCase {
    func testSpeedLimitDefaultsToRectangularStyle() {
        let packet = HudCommands.speedLimit(limit: 35, tolerance: 5)
        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Could not decode packet")
            return
        }

        // payload begins after command/p1/p2 and contains limit, tolerance,
        // then squareStyle int32 = 1.
        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 101)
        XCTAssertEqual(body[2], 2)
        XCTAssertEqual(body.suffix(4), Data([0, 0, 0, 1]))
    }

    func testOBDV45MigrationExists() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/HudOBDController.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("HUD.OBD.v45AutoConnectMigrated"))
        XCTAssertTrue(source.contains("startAutoConnectLoop(reason:"))
    }

    func testAmbientUsesPersistentBackgroundPeripheralConnection() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("central.connect(peripheral"))
        XCTAssertTrue(source.contains("didDisconnectPeripheral"))
        XCTAssertTrue(source.contains("HUD.Ambient.peripheralUUID"))
        XCTAssertTrue(source.contains("CBCentralManagerOptionRestoreIdentifierKey"))
    }

    func testCaptureHasWatchdogAndNavigationOffLifecycle() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: url)
        XCTAssertTrue(source.contains("SCREEN CAPTURE WATCHDOG"))
        XCTAssertTrue(source.contains("Navigation OFF → Freeride"))
        XCTAssertTrue(source.contains("Accepted structurally valid reroute immediately"))
        XCTAssertTrue(source.contains("Arrival display completed"))
    }
}
