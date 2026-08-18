import XCTest
@testable import HUDController

final class V81MergeTestAccessGuardTests: XCTestCase {
    func testMergeRegressionUsesPublicParserSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let testSource = try String(
            contentsOf: root.appendingPathComponent(
                "HUDControllerTests/V80GoogleMergeCardTests.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            testSource.contains("ExternalNavigationOCRParser.parse(")
        )
        XCTAssertFalse(
            testSource.contains(
                "ExternalNavigationOCRParser.isExplicitGoogleManeuver("
            )
        )
        XCTAssertFalse(
            testSource.contains(
                "ExternalNavigationOCRParser.maneuverFromText("
            )
        )
    }
}
