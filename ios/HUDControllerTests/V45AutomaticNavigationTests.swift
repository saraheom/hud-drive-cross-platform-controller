import XCTest
@testable import HUDController

final class V45AutomaticNavigationTests: XCTestCase {
    func testGoogleMapsAutoDetection() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "Directions",
                "In 300 ft",
                "Turn right onto W Roosevelt Blvd",
                "0.7 miles",
                "Keep left to stay on W Roosevelt Blvd"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .googleMaps)
        XCTAssertEqual(result.screenState, .active)
        XCTAssertTrue(result.isValidNavigation)
        XCTAssertEqual(result.instruction.maneuver, .right)
    }

    func testAppleMapsProceedToRouteIsActiveNavigation() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "Proceed to the route",
                "400 ft",
                "13 N 38th St",
                "450 ft",
                "13 Powelton Ave",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.screenState, .approachRoute)
        XCTAssertTrue(result.isValidNavigation)
        XCTAssertEqual(result.instruction.primaryText, "Proceed to the route")
    }

    func testAppleMapsRouteListAutoDetection() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "70 ft",
                "13 N 38th St",
                "450 ft",
                "13 Powelton Ave",
                "0.4 mi",
                "N 33rd St",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.screenState, .active)
        XCTAssertTrue(result.isValidNavigation)
        XCTAssertEqual(result.originalDistanceText, "70 ft")
        XCTAssertTrue((20...23).contains(result.instruction.distanceMeters))
    }

    func testGoogleHomeIsInactive() {
        let result = ExternalNavigationOCRParser.parse(
            lines: ["Search here", "Google Maps", "Explore", "You", "Contribute"],
            rawText: ""
        )
        XCTAssertEqual(result.source, .googleMaps)
        XCTAssertEqual(result.screenState, .inactive)
    }

    func testAppleHomeIsInactive() {
        let result = ExternalNavigationOCRParser.parse(
            lines: ["86°", "Apple Maps", "3D"],
            rawText: ""
        )
        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertEqual(result.screenState, .inactive)
    }
}
