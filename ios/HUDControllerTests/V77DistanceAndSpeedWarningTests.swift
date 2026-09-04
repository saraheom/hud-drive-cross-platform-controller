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

    func testHudManeuverUsesNativeDistanceFieldWithoutDuplicatingSourceDistanceInText() {
        let instruction = NavigationInstruction(
            maneuver: .right,
            distanceMeters: 321,
            primaryText: "Turn right",
            streetName: "N 34th St",
            displayDistanceText: "0.2 mi",
            currentStreet: "N 33rd St"
        )

        let packet = HudCommands.maneuver(instruction)
        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("maneuver packet did not unescape")
            return
        }

        XCTAssertEqual(Data(body.prefix(3)), Data([2, 100, 1]))
        XCTAssertGreaterThanOrEqual(body.count, 5)

        let utfLength = Int((UInt16(body[3]) << 8) | UInt16(body[4]))
        let textStart = 5
        let textEnd = textStart + utfLength
        guard textEnd + 12 <= body.count else {
            XCTFail("maneuver packet was shorter than expected")
            return
        }

        let renderedText = String(
            data: body.subdata(in: textStart..<textEnd),
            encoding: .utf8
        )
        XCTAssertEqual(renderedText, "Turn right\nN 34th St\nN 33rd St")
        XCTAssertFalse(renderedText?.contains("0.2 mi") ?? true)
        XCTAssertFalse(renderedText?.contains("•") ?? true)

        // After the UTF text: maneuver type (Int32), direction (Int32),
        // then the native HUD distance field (Int32, big-endian meters).
        let distanceOffset = textEnd + 8
        let distance =
            (UInt32(body[distanceOffset]) << 24) |
            (UInt32(body[distanceOffset + 1]) << 16) |
            (UInt32(body[distanceOffset + 2]) << 8) |
            UInt32(body[distanceOffset + 3])
        XCTAssertEqual(distance, 321)
    }

    func testLegalSignAndGaugeWarningAreSeparated() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )

        XCTAssertTrue(source.contains("tolerance: 0"))
        XCTAssertTrue(source.contains("sendOriginalAutomaticSpeedWarning"))
        XCTAssertTrue(source.contains("HudCommands.speedWarningThreshold(legalLimitMph)"))
        XCTAssertFalse(source.contains("speedTolerance"))
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
