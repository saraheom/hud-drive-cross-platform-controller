import XCTest
@testable import HUDWAYController

final class HudwayProtocolTests: XCTestCase {
    func testKeepAlive() {
        XCTAssertEqual(HudwayProtocol.hex(HudwayCommands.keepAlive()), "02 7D 7F 0F 00 03")
    }

    func testUARTConnectionCheck() {
        XCTAssertEqual(HudwayProtocol.hex(HudwayCommands.uartConnectionCheck()), "02 7D 7F 06 00 03")
    }

    func testTimeWeatherOff() {
        XCTAssertEqual(HudwayProtocol.hex(HudwayCommands.timeWeather(false)), "02 7D 7F 09 04 00 03")
    }

    func testUARTEventDetection() {
        let data = Data([0x02,0x7D,0x7E,0x01,0x01,0xFF,0xFF,0xFF,0xFF,0x03])
        XCTAssertTrue(HudwayProtocol.isUARTConnectionEvent(data))
    }

    func testRightManeuverHeader() {
        let instruction = NavigationInstruction(
            maneuver: .right, distanceMeters: 46,
            primaryText: "Turn right", streetName: "Main St"
        )
        let packet = HudwayCommands.maneuver(instruction)
        XCTAssertEqual(packet.first, 0x02)
        XCTAssertEqual(packet.last, 0x03)
    }
}
