import XCTest
@testable import HUDController

final class V80GoogleMergeSourceGuardTests: XCTestCase {
    func testSpatialPairingUsesExpandedExplicitManeuverGate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/GoogleMapsOCRParser.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("s.contains(\"merge\")"))
        XCTAssertTrue(source.contains("s.hasPrefix(\"use the \")"))
        XCTAssertTrue(source.contains("s.contains(\" lane \")"))
        XCTAssertTrue(source.contains("spatialCurrentGoogleCard"))
    }
}
