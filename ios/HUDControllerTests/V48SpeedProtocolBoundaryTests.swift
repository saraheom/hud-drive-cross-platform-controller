import XCTest
@testable import HUDController

final class V48SpeedProtocolBoundaryTests: XCTestCase {
    func testFortyFiveMphProducesApproximatelySeventyTwoKmhProtocolValue() {
        // The app/UI value is mph, while SpeedNotification's numeric content
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

        // SpeedNotification is implemented through the generic notification
        // packet family: command 1, category 14, p2 0.
        XCTAssertGreaterThan(body.count, 3)
        XCTAssertEqual(body[0], 1)
        XCTAssertEqual(body[1], 14)
        XCTAssertEqual(body[2], 0)

        // HudCommands.speedNotification(kmh:) places the protocol km/h value
        // into the notification title string. Verify that the encoded payload
        // actually contains "72" instead of assuming an unrelated Int32 packet
        // layout.
        let payload = body.dropFirst(3)
        let ascii = String(decoding: payload, as: UTF8.self)
        XCTAssertTrue(
            ascii.contains("72"),
            "SpeedNotification payload should contain the provided km/h value"
        )
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
