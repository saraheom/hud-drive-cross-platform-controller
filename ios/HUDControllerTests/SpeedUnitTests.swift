import XCTest
@testable import HUDController

final class SpeedUnitTests: XCTestCase {
    func testVehicleViewUsesMPHLabels() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/UI/VehicleView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("mph"))
        XCTAssertFalse(source.contains("km/h"))
    }

    func testSpeedEngineUsesMPHConversions() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("2.2369362920544"))
        XCTAssertTrue(source.contains("0.62137119223733"))
        XCTAssertFalse(source.contains("* 3.6"))
    }
}
