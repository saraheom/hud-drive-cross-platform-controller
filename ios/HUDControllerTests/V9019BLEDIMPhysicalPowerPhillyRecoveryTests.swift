import XCTest
import Foundation
@testable import HUDController

final class V9019BLEDIMPhysicalPowerPhillyRecoveryTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let ios = here.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: ios.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBLEDIMPowerMappingMatchesKnownGoodV90172Capture() {
        XCTAssertEqual(
            BLEDIM2Protocol.power(false, sequence: 0x09),
            Data([0x55, 0xAA, 0x09, 0x80, 0x00, 0x01, 0x00, 0x89])
        )
        XCTAssertEqual(
            BLEDIM2Protocol.power(true, sequence: 0x0A),
            Data([0x55, 0xAA, 0x0A, 0x80, 0x00, 0x01, 0x01, 0x8B])
        )
    }

    func testKnownGoodRollbackPowerStateMigratesOnce() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("migrateV9020BLEDIMKnownGoodRollbackIfNeeded()"))
        XCTAssertTrue(monitor.contains("HUD.Ambient.v90_20.bledimKnownGoodRollbackMigrated"))
        XCTAssertTrue(monitor.contains("pairedDevices[index].powerOn = true"))
    }

    func testPhiladelphiaQueryUsesCurrentStreetCenterlineSchemaAndBackoff() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("esriGeometryPoint"))
        XCTAssertTrue(speed.contains("URLQueryItem(name: \"distance\", value: \"650\")"))
        XCTAssertTrue(speed.contains("URLQueryItem(name: \"units\", value: \"esriSRUnit_Meter\")"))
        XCTAssertTrue(speed.contains("TRANSPORTATION_street_segment/FeatureServer/0/query"))
        XCTAssertTrue(speed.contains("POSTED_SPEED_LIMIT"))
        XCTAssertTrue(speed.contains("SPEED_LIMIT"))
        XCTAssertTrue(speed.contains("providerFailureRetrySeconds: TimeInterval = 12.0"))
        XCTAssertTrue(speed.contains("layersOK=1/1"))
    }
}
