import XCTest
@testable import HUDController

final class V71ExactDistanceUS1Tests: XCTestCase {
    func testNavigationInstructionCanPreserveOriginalDistanceText() {
        let instruction = NavigationInstruction(
            maneuver: .straight,
            distanceMeters: 25,
            primaryText: "Straight",
            streetName: "Lansdowne Dr",
            displayDistanceText: "80 ft"
        )

        XCTAssertEqual(instruction.distanceMeters, 25)
        XCTAssertEqual(instruction.displayDistanceText, "80 ft")
    }

    func testAppleParserStoresExactDistanceStringInInstruction() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "80 ft",
                "Lansdowne Dr",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.instruction.distanceMeters, 24)
        XCTAssertEqual(result.instruction.displayDistanceText, "80 ft")
        XCTAssertEqual(result.originalDistanceText, "80 ft")
    }

    func testUS1FallbackUsesDarkNumeralInsideLightShield() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/GoogleMapsOCRParser.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("light shield"))
        XCTAssertTrue(source.contains("if luminance(x, y) <= 90"))
        XCTAssertTrue(source.contains("return \"1\""))

        // v70's incorrect white-digit assumption must not remain.
        XCTAssertFalse(source.contains("numeral itself is close to white"))
    }

    func testNavigationUIUsesExactInstructionDistanceText() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/UI/HudNavigationView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("instruction.displayDistanceText"))
        XCTAssertTrue(source.contains("Text(distanceText(state.navigation.current))"))
        XCTAssertTrue(source.contains("distanceText(capture.latestInstruction)"))
    }
}
