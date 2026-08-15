import XCTest
@testable import HUDController

final class V63AppleShieldBehaviorTests: XCTestCase {
    func testUSRouteShieldIsPreservedInStreetName() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "150 ft",
                "13",
                "Powelton Ave",
                "0.4 mi",
                "N 33rd St",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.instruction.streetName, "US 13 Powelton Ave")
    }
}
