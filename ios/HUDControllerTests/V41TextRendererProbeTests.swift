import XCTest
@testable import HUDController

final class V41TextRendererProbeTests: XCTestCase {
    func testWeatherIsRestoredAsWeather() {
        XCTAssertEqual(HudSideWidget.weather.rawValue, "Weather")
        XCTAssertEqual(HudSideWidget.weather.displayName, "Weather")
    }

    func testGenericNotificationProbeCarriesText() {
        let packet = HudCommands.textNotificationProbe(
            category: 7,
            packageName: "probe.pkg",
            title: "TEST ARTIST",
            message: "TEST TRACK"
        )

        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Could not unescape packet")
            return
        }

        XCTAssertEqual(body[0], 1)
        XCTAssertEqual(body[1], 7)
        XCTAssertEqual(body[2], 0)
    }

    func testPhoneNameProbeCarriesUTFText() {
        let packet = HudCommands.phoneName("TEST ARTIST | TEST TRACK")
        let body = HudProtocol.unescape(packet)
        XCTAssertEqual(body?[0], 2)
        XCTAssertEqual(body?[1], 123)
        XCTAssertEqual(body?[2], 0)
    }

    func testNavigationProbeUsesKnownManeuverRenderer() {
        let packet = HudCommands.persistentNavigationTextProbe(
            title: "TEST ARTIST",
            detail: "TEST TRACK"
        )
        let body = HudProtocol.unescape(packet)
        XCTAssertEqual(body?[0], 2)
        XCTAssertEqual(body?[1], 100)
        XCTAssertEqual(body?[2], 1)
    }
}
