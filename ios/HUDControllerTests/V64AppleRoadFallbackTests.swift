import XCTest
@testable import HUDController

final class V64AppleRoadFallbackTests: XCTestCase {
    func testDirectionalRoadTextStillParsesWhenShieldTextIsMissing() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "0.4 mi",
                "North",
                "4.0 mi",
                "Rising Sun Ave",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.instruction.streetName, "North")
        XCTAssertTrue(result.isValidNavigation)
    }
}
