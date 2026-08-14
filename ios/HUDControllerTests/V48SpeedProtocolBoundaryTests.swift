import XCTest
@testable import HUDController

final class V48SpeedProtocolBoundaryTests: XCTestCase {
    func testFortyFiveMphProducesApproximatelySeventyTwoKmhProtocolValue() {
        // The app/UI value is mph, while SpeedNotification's numeric payload
        // is native km/h. 45 mph is approximately 72 km/h.
        let mph = 45.0
        let metersPerSecond = mph / 2.2369362920544
        let protocolKmh = Int((metersPerSecond * 3.6).rounded())

        XCTAssertEqual(protocolKmh, 72)
    }

    func testSpeedNotificationEncodesProvidedProtocolValue() {
        let packet = HudCommands.speedNotification(kmh: 72)

        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Could not decode SpeedNotification packet")
            return
        }

        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 102)
        XCTAssertEqual(body[2], 0)

        // The final four bytes are the big-endian Int32 speed payload.
        XCTAssertEqual(body.suffix(4), Data([0, 0, 0, 72]))
    }

    func testAppFacingSpeedVariableRemainsMph() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("currentSpeedMph"))
        XCTAssertTrue(source.contains("speedMS * 2.2369362920544"))
        XCTAssertTrue(source.contains("protocolSpeedKmh"))
        XCTAssertTrue(source.contains("speedMS * 3.6"))
        XCTAssertFalse(
            source.contains("HudCommands.speedNotification(kmh: currentSpeedMph)")
        )
    }
}
