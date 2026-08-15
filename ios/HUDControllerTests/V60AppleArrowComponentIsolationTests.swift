import XCTest
@testable import HUDController

final class V60AppleArrowComponentIsolationTests: XCTestCase {
    func testSimpleAppleArrowUsesConnectedComponentIsolation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("dominantArrowComponent(from: data)"))
        XCTAssertTrue(source.contains("componentArrowScore"))
        XCTAssertTrue(source.contains("upperLeft"))
        XCTAssertTrue(source.contains("upperRight"))
    }

    func testLaneGuidanceClassifierRemainsSeparate() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("classifyHighlightedLaneArrow"))
        XCTAssertTrue(source.contains("if let lane = classifyHighlightedLaneArrow"))
    }

    func testOldWholeCropEdgeHeuristicIsGone() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(source.contains("leftTipByMass"))
        XCTAssertFalse(source.contains("rightTipByMass"))
    }
}
