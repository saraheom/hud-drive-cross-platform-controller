import XCTest
@testable import HUDController

final class ScreenCaptureBuildGuardTests: XCTestCase {
    func testGoogleMapsParserStillCompilesWithoutLiveScreenCapture() {
        let result = GoogleMapsOCRParser.parse(
            lines: [
                "Directions",
                "In 300 ft",
                "Turn right onto W Roosevelt Blvd"
            ],
            rawText: "test"
        )

        XCTAssertEqual(result.instruction.maneuver, .right)
        XCTAssertEqual(result.instruction.streetName, "W Roosevelt Blvd")
        XCTAssertTrue((85...100).contains(result.instruction.distanceMeters))
    }
}
