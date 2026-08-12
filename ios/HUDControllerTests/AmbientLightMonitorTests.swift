import XCTest
@testable import HUDController

final class AmbientLightMonitorTests: XCTestCase {
    func testAmbientMonitorDoesNotRequireStateRestoration() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/AmbientLightMonitor.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("CBCentralManagerOptionRestoreIdentifierKey"),
            "Ambient monitor must either omit a restoration identifier or implement willRestoreState."
        )
    }
}
