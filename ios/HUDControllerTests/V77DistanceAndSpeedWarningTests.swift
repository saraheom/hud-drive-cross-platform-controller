import XCTest
@testable import HUDController

final class V77DistanceAndSpeedWarningTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testExactGoogleMilesTextIsPreserved() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "Directions",
                "In 2.4 mi",
                "Turn right onto Falls Bridge"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.instruction.displayDistanceText, "In 2.4 mi")
        XCTAssertEqual(result.instruction.distanceMeters, 3862)
    }

    func testExactFeetUsesNearestIntegerMeterNotCeilBias() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "80 ft",
                "Lansdowne Dr",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.instruction.displayDistanceText, "80 ft")
        XCTAssertEqual(result.instruction.distanceMeters, 24)
    }

    func testHudManeuverTextCarriesExactSourceDistance() throws {
        let source = try source(
            "HUDController/Protocol/HudCommands.swift"
        )

        XCTAssertTrue(source.contains("normalizedSourceDistanceText"))
        XCTAssertTrue(source.contains("primaryWithDistance"))
        XCTAssertTrue(source.contains("• \\(exactDistance)"))
        XCTAssertTrue(source.contains("instruction.distanceMeters"))
    }

    func testLegalSignAndGaugeWarningAreSeparated() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )

        XCTAssertTrue(source.contains("tolerance: 0"))
        XCTAssertTrue(source.contains("sendOverspeedGaugeThreshold"))
        XCTAssertTrue(source.contains("legalLimitMph + speedTolerance"))
        XCTAssertTrue(source.contains("HudCommands.speedWarningThreshold(threshold)"))
    }

    func testCrashStabilitySerializationStillPresent() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("recoveryInFlight"))
        XCTAssertTrue(source.contains("serialized recovery attempt="))
        XCTAssertTrue(source.contains("self.lastFrameAt = nil"))
    }
}
