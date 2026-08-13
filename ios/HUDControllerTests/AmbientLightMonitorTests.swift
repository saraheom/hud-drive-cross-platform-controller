import XCTest
@testable import HUDController

final class AmbientLightMonitorTests: XCTestCase {
    func testAmbientMonitorRestorationIsImplementedConsistently() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let usesRestorationIdentifier =
            source.contains("CBCentralManagerOptionRestoreIdentifierKey")
        let implementsRestoreCallback =
            source.contains("willRestoreState dict:")

        XCTAssertEqual(
            usesRestorationIdentifier,
            implementsRestoreCallback,
            "If CoreBluetooth state restoration is enabled, AmbientLightMonitor must implement centralManager(_:willRestoreState:)."
        )

        // v30+ intentionally enables restoration so the BLEDOM monitor has
        // the best available background/locked-screen behavior.
        XCTAssertTrue(usesRestorationIdentifier)
        XCTAssertTrue(implementsRestoreCallback)
    }

    func testAmbientTimeoutSupportsOneSecond() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("max(1, d.integer(forKey:"))
    }
}
