import XCTest
@testable import HUDController

final class VehiclePacketTests: XCTestCase {
    func testOBDConnectionPacketShape() {
        let data = HudCommands.obdConnection(enabled: true, deviceName: "OBDII")
        XCTAssertEqual(data.first, 0x02)
        XCTAssertEqual(data.last, 0x03)
        let body = HudProtocol.unescape(data)
        XCTAssertEqual(body?[0], 0)
        XCTAssertEqual(body?[1], 7)
        XCTAssertEqual(body?[2], 1)
    }

    func testSpeedLimitPacketShape() {
        let data = HudCommands.speedLimit(limit: 35, tolerance: 5)
        let body = HudProtocol.unescape(data)
        XCTAssertEqual(body?[0], 2)
        XCTAssertEqual(body?[1], 101)
        XCTAssertEqual(body?[2], 2)
    }

    func testMusicPacketCategory() {
        let data = HudCommands.musicNotification(artist: "Artist", track: "Track")
        let body = HudProtocol.unescape(data)
        XCTAssertEqual(body?[0], 1)
        XCTAssertEqual(body?[1], 12)
        XCTAssertEqual(body?[2], 0)
    }
}
