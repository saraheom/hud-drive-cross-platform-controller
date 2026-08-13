import XCTest
@testable import HUDController

final class V38DashboardProtocolTests: XCTestCase {
    func testTripTimeUsesOriginalDashName() {
        XCTAssertEqual(HudSideWidget.tripTime.rawValue, "TripTime")
    }

    func testOriginalSideWidgetNames() {
        XCTAssertEqual(HudSideWidget.distance.rawValue, "TraveledDistance")
        XCTAssertEqual(HudSideWidget.coolantTemperature.rawValue, "EngineCoolantTemp")
        XCTAssertEqual(HudSideWidget.fuelConsumption.rawValue, "GasolineConsumption")
    }

    func testFreerideDashboardPacketIs111() {
        let packet = HudCommands.dashboard(
            left: HudSideWidget.distance.rawValue,
            center: "Simple",
            right: HudSideWidget.tripTime.rawValue,
            navigationLayout: false
        )
        let body = HudProtocol.unescape(packet)
        XCTAssertEqual(body?[0], 2)
        XCTAssertEqual(body?[1], 111)
        XCTAssertEqual(body?[2], 0)
    }

    func testMusicUsesFirmwarePackage() {
        let packet = HudCommands.musicNotification(artist: "Artist", track: "Track")
        let body = HudProtocol.unescape(packet)
        XCTAssertNotNil(body)
        XCTAssertTrue(String(data: body ?? Data(), encoding: .utf8)?.contains("com.kivic.music") == true)
    }
}
