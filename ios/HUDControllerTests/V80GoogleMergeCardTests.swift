import XCTest
@testable import HUDController

final class V80GoogleMergeCardTests: XCTestCase {
    func testUseLeftLaneToMergeIsExplicitCurrentManeuver() {
        XCTAssertTrue(
            ExternalNavigationOCRParser.isExplicitGoogleManeuver(
                "Use the left lane to merge onto Eakins Ovl/Martin Luther King Jr Dr/Spring Garden St"
            )
        )
    }

    func testUseRightLaneToMergeIsExplicitCurrentManeuver() {
        XCTAssertTrue(
            ExternalNavigationOCRParser.isExplicitGoogleManeuver(
                "Use the right lane to merge onto I-76"
            )
        )
    }

    func testMergeMapsToStraightEvenThoughTextContainsLeft() {
        XCTAssertEqual(
            ExternalNavigationOCRParser.maneuverFromText(
                "Use the left lane to merge onto Eakins Ovl"
            ),
            .straight
        )
    }

    func testExactScreenshotLayoutChoosesTopMergeNotNext200FootTurn() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "Directions",
                "In 0.1 mi",
                "Use the left lane to merge onto Eakins Ovl/Martin Luther King Jr Dr/Spring Garden St",
                "200 feet",
                "Use the left lane to continue on Eakins Ovl/Martin Luther King Jr Dr",
                "0 feet",
                "Use the left lane to turn slightly left onto Benjamin Franklin Pkwy/Eakins Ovl",
                "0.2 miles",
                "Use the left lane to turn slightly left onto Eakins Ovl/Spring Garden St",
                "200 feet",
                "Turn left onto Benjamin Franklin Pkwy/Eakins Ovl",
                "0.1 miles",
                "Continue straight onto John B Kelly Dr/Kelly Dr"
            ],
            rawText: ""
        )

        XCTAssertTrue(result.isValidNavigation)
        XCTAssertEqual(result.source, .googleMaps)
        XCTAssertEqual(result.instruction.maneuver, .straight)
        XCTAssertEqual(result.instruction.distanceMeters, 161)
        XCTAssertEqual(result.instruction.displayDistanceText, "In 0.1 mi")
        XCTAssertTrue(result.instruction.streetName.contains("Eakins"))
        XCTAssertEqual(result.instruction.primaryText, "Continue straight")
    }
}
