import XCTest
@testable import HUDController

final class V57NavigationCaptureMusicLabTests: XCTestCase {
    func testPushMessagePacketUsesOriginalHiddenCommand() {
        let packet = HudCommands.pushMessage(
            position: 1,
            type: 0,
            title: "Artist",
            message: "Track"
        )
        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Could not decode packet")
            return
        }

        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 24)
        XCTAssertEqual(body[2], 0)
        XCTAssertEqual(body[3...6], Data([0, 0, 0, 1]))
    }

    func testGoogleDestinationWillBeIsApproachNotArrival() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "Directions",
                "In 0.4 mi",
                "Home",
                "Destination will be on the left"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .googleMaps)
        XCTAssertEqual(result.screenState, .active)
        XCTAssertTrue(result.isValidNavigation)
        XCTAssertEqual(result.instruction.distanceMeters, 644)
        XCTAssertEqual(result.instruction.primaryText, "Destination on left")
    }

    func testLongGoogleInstructionCompactsToTurnAndRoad() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "Directions",
                "In 1.1 mi",
                "Turn left after the gas station (on the left) onto Adams Ave",
                "200 feet",
                "Continue straight past Sunoco to stay on Adams Ave"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.instruction.maneuver, .left)
        XCTAssertEqual(result.instruction.primaryText, "Turn left")
        XCTAssertEqual(result.instruction.streetName, "Adams Ave")
    }

    func testApplePureShieldNumberIsPreservedAsUSRouteText() {
        let result = ExternalNavigationOCRParser.parse(
            lines: [
                "0.4 mi",
                "1",
                "North",
                "4.0 mi",
                "Rising Sun Ave",
                "End Route"
            ],
            rawText: ""
        )

        XCTAssertEqual(result.source, .appleMaps)
        XCTAssertTrue(result.instruction.streetName.contains("US 1"))
        XCTAssertTrue(result.instruction.streetName.contains("North"))
    }

    func testCaptureUsesSystemNotificationForBackgroundRecovery() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/ExternalNavigationCapture.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("HUD screen capture paused"))
        XCTAssertTrue(source.contains("forceFreerideForCaptureLoss"))
        XCTAssertTrue(source.contains("captureLossGeneration"))
        XCTAssertTrue(source.contains("age > 4"))
    }

    func testSpeedLimitStylePrimeUsesRectangularPacketBeforeRoadLookup() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("func primeRectangularStyle()"))
        XCTAssertTrue(source.contains("HudCommands.speedLimit(limit: 0"))
    }
}
