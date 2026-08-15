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

    func testAmbientTimeoutSupportsOneSecondWithoutRecursiveDidSet() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // v51 moved clamping out of the property observer because assigning
        // absenceTimeoutSeconds from its own didSet can recurse/crash.
        XCTAssertTrue(
            source.contains("static func clampedTimeout(_ value: Int) -> Int { max(1, min(30, value)) }")
        )
        XCTAssertTrue(
            source.contains("func setAbsenceTimeout(_ value: Int)")
        )
        XCTAssertTrue(
            source.contains("absenceTimeoutSeconds = Self.clampedTimeout(value)")
        )

        // Persisted values are also clamped through the same safe helper.
        XCTAssertTrue(
            source.contains("Self.clampedTimeout(d.integer(forKey: \"HUD.Ambient.timeout\"))")
        )

        // Regression guard: the observer must not assign the property to
        // itself again.
        guard let propertyStart = source.range(of: "var absenceTimeoutSeconds: Int {"),
              let helperStart = source.range(of: "static func clampedTimeout", range: propertyStart.upperBound..<source.endIndex)
        else {
            XCTFail("Ambient timeout property/helper not found")
            return
        }

        let propertyBlock = String(source[propertyStart.lowerBound..<helperStart.lowerBound])
        XCTAssertFalse(
            propertyBlock.contains("absenceTimeoutSeconds ="),
            "absenceTimeoutSeconds didSet must not recursively assign itself"
        )
    }
}
