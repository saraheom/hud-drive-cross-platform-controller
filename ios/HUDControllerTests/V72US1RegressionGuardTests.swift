import XCTest
@testable import HUDController

final class V72US1RegressionGuardTests: XCTestCase {
    func testUS1FallbackArchitectureWithoutPinningOldGeometryThreshold() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/GoogleMapsOCRParser.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("detectUSRouteOne"))
        XCTAssertTrue(source.contains("lightComponents"))
        XCTAssertTrue(source.contains("darkComponents"))
        XCTAssertTrue(source.contains("shieldCandidates"))
    }
}
