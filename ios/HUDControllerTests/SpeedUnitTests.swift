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

        // App-facing speed remains mph.
        XCTAssertTrue(source.contains("currentSpeedMph"))
        XCTAssertTrue(source.contains("speedMS * 2.2369362920544"))

        // The physical HUD protocol's SpeedNotification numeric field is km/h
        // even when the HUD itself is configured to display mph. The engine
        // must therefore convert m/s -> km/h only at the BLE packet boundary.
        XCTAssertTrue(source.contains("protocolSpeedKmh"))
        XCTAssertTrue(source.contains("speedMS * 3.6"))
        XCTAssertTrue(
            source.contains("HudCommands.speedNotification(kmh: protocolSpeedKmh)")
        )

        // Regression guard: never send the mph number directly into the
        // protocol field again; that caused ~0.62x displayed speed.
        XCTAssertFalse(
            source.contains("HudCommands.speedNotification(kmh: currentSpeedMph)")
        )
    }

    func testSpeedParserTupleMemberNamesMatch() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("parsed.sourceWasMph"))
        XCTAssertFalse(source.contains("parsed.isMph"))
    }

}
