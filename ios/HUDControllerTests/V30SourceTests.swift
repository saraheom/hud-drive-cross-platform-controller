import XCTest
@testable import HUDController

final class V30SourceTests: XCTestCase {
    func testOCRParserExample() {
        let parsed = GoogleMapsOCRParser.parse(
            lines: ["Directions", "In 300 ft", "Turn right onto W Roosevelt Blvd", "0.7 miles"],
            rawText: ""
        )
        XCTAssertEqual(parsed.instruction.maneuver, .right)
        XCTAssertEqual(parsed.instruction.streetName, "W Roosevelt Blvd")
        XCTAssertTrue((85...100).contains(parsed.instruction.distanceMeters))
    }
}
