import XCTest
@testable import HUDController

final class V9031CarPlayRouteGuidanceTests: XCTestCase {
    func testOriginalHudEtaPacketShape() {
        let arrival: Int64 = 1_788_441_853_000
        let packet = HudCommands.eta(arrivalTimeMilliseconds: arrival)
        let body = HudProtocol.unescape(packet)
        XCTAssertNotNil(body)
        XCTAssertEqual(body?.prefix(3), Data([2, 114, 0]))
        XCTAssertEqual(body?.dropFirst(3), HudProtocol.int64(arrival))
    }

    func testNavigationSourcePriority() {
        XCTAssertGreaterThan(
            RouteGuidanceAdapterClient.SourceKind.googleMaps.priority,
            RouteGuidanceAdapterClient.SourceKind.appleMaps.priority
        )
        XCTAssertGreaterThan(
            RouteGuidanceAdapterClient.SourceKind.appleMaps.priority,
            RouteGuidanceAdapterClient.SourceKind.waze.priority
        )
    }

    func testSourceClassification() {
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Google Maps"), .googleMaps)
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Apple Maps"), .appleMaps)
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Maps"), .appleMaps)
        XCTAssertEqual(RouteGuidanceAdapterClient.SourceKind.classify("Waze"), .waze)
    }
}
