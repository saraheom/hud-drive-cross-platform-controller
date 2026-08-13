import XCTest
@testable import HUDController

final class V39NavigationValidationTests: XCTestCase {
    func testGoogleMapsCarPlayExampleIsValid() {
        let parsed = GoogleMapsOCRParser.parse(
            lines: [
                "Directions",
                "In 300 ft",
                "Turn right onto W Roosevelt Blvd",
                "0.7 miles",
                "Keep left to stay on W Roosevelt Blvd"
            ],
            rawText: ""
        )

        XCTAssertTrue(parsed.isValidNavigation)
        XCTAssertGreaterThanOrEqual(parsed.confidence, 80)
        XCTAssertEqual(parsed.instruction.maneuver, .right)
        XCTAssertEqual(parsed.instruction.streetName, "W Roosevelt Blvd")
    }

    func testOwnCaptureUIIsRejected() {
        let parsed = GoogleMapsOCRParser.parse(
            lines: [
                "Keep screen awake during capture",
                "46 m",
                "Automatically send parsed maneuver to HUD"
            ],
            rawText: ""
        )

        XCTAssertFalse(parsed.isValidNavigation)
    }

    func testRandomDistanceWithoutManeuverIsRejected() {
        let parsed = GoogleMapsOCRParser.parse(
            lines: ["Battery", "150 ft", "Settings"],
            rawText: ""
        )
        XCTAssertFalse(parsed.isValidNavigation)
    }

    func testWeatherWidgetRemainsOriginalFirmwareWidget() {
        XCTAssertEqual(HudSideWidget.weather.rawValue, "Weather")
        XCTAssertEqual(HudSideWidget.weather.displayName, "Weather")
    }
}
