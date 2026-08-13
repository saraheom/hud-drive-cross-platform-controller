import XCTest
@testable import HUDController

final class V40MusicWeatherSlotTests: XCTestCase {
    func testMusicIsBackedByOriginalWeatherToken() {
        XCTAssertEqual(HudSideWidget.weather.rawValue, "Weather")
        XCTAssertEqual(HudSideWidget.weather.displayName, "Music")
        XCTAssertTrue(HudSideWidget.weather.isMusicDisplaySlot)
    }

    func testNoUndocumentedMusicDashboardTokenRemains() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Models/HudDashboardWidget.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("spotifyMusicExperimental"))
        XCTAssertFalse(source.contains(#"case spotifyMusicExperimental = "Music""#))
    }

    func testDashboardPacketStillCarriesWeatherForMusicSlot() {
        let packet = HudCommands.dashboard(
            left: HudSideWidget.weather.rawValue,
            center: "Simple",
            right: HudSideWidget.tripTime.rawValue,
            navigationLayout: false
        )

        guard let body = HudProtocol.unescape(packet),
              let payloadString = String(data: body, encoding: .utf8) else {
            XCTFail("Unable to inspect dashboard packet")
            return
        }

        XCTAssertTrue(payloadString.contains("Weather"))
        XCTAssertTrue(payloadString.contains("TripTime"))
    }
}
