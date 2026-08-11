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

    func testNotificationMasterOn() {
        XCTAssertEqual(
            HudwayProtocol.hex(HudwayCommands.notificationsMasterEnabled(true)),
            "02 7D 7F 09 07 01 03"
        )
    }

    func testNotificationInit() {
        XCTAssertEqual(
            HudwayProtocol.hex(HudwayCommands.notificationSettingsInit()),
            "02 7D 7F 09 06 03"
        )
    }

    func testNotificationTimeout10Seconds() {
        XCTAssertEqual(
            HudwayProtocol.hex(HudwayCommands.notificationTimeout(seconds: 10)),
            "02 7D 7F 09 01 00 00 00 0A 03"
        )
    }

    func testNotificationFiveLines() {
        XCTAssertEqual(
            HudwayProtocol.hex(HudwayCommands.notificationLineCount(5)),
            "02 7D 7F 74 00 00 00 00 05 03"
        )
    }

}
