import XCTest
@testable import HUDController

final class V60AppleArrowComponentIsolationTests: XCTestCase {
    func testSimpleAppleArrowUsesConnectedComponentIsolation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        // v60+ still isolates the maneuver glyph first.
        XCTAssertTrue(source.contains("dominantArrowComponent(from: data)"))
        XCTAssertTrue(source.contains("componentArrowScore"))
        XCTAssertTrue(source.contains("connected bright-pixel components"))

        // v62 classifies the isolated component using the measured
        // extreme-edge arrow-tip versus stem invariant.
        XCTAssertTrue(source.contains("let leftEdge = glyph.filter"))
        XCTAssertTrue(source.contains("let rightEdge = glyph.filter"))
        XCTAssertTrue(source.contains("let leftIsTip"))
        XCTAssertTrue(source.contains("let rightIsTip"))

        // The superseded upper-half classifier must remain gone.
        XCTAssertFalse(source.contains("let upperCut = minY + Int(Double(bh) * 0.60)"))
        XCTAssertFalse(source.contains("let upperLeft ="))
        XCTAssertFalse(source.contains("let upperRight ="))
        XCTAssertFalse(source.contains("let normalizedShift ="))
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
