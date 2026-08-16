import XCTest
@testable import HUDController

final class V70ImperialUnitsAndUS1Tests: XCTestCase {
    func testImperialUnitPacketMatchesOriginalProtocol() {
        let packet = HudCommands.imperialUnits()
        guard let body = HudProtocol.unescape(packet) else {
            XCTFail("Could not decode packet")
            return
        }

        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 9)
        XCTAssertEqual(body[2], 5)
        XCTAssertEqual(Data(body[3...6]), Data([0, 0, 0, 1]))
    }

    func testNavigationReassertsImperialUnitsBeforeManeuver() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/HudNavigationController.swift"
            ),
            encoding: .utf8
        )

        guard let unit = source.range(of: "HudCommands.imperialUnits()"),
              let maneuver = source.range(of: "HudCommands.maneuver(current)")
        else {
            XCTFail("Expected unit/maneuver commands not found")
            return
        }

        XCTAssertLessThan(unit.lowerBound, maneuver.lowerBound)
    }

    func testUS1VisualFallbackExists() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Navigation/GoogleMapsOCRParser.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("detectUSRouteOne"))
        XCTAssertTrue(source.contains("return \"1\""))
        XCTAssertTrue(source.contains("Double(ch) / Double(max(1, cw)) >= 1.65"))
    }
}
