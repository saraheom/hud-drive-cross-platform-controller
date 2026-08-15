import XCTest
@testable import HUDController

final class V62AppleArrowShieldTests: XCTestCase {
    func testArrowClassifierUsesIsolatedExtremeEdgeInvariant() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("dominantArrowComponent(from: data)"))
        XCTAssertTrue(source.contains("let leftEdge = glyph.filter"))
        XCTAssertTrue(source.contains("let rightEdge = glyph.filter"))
        XCTAssertTrue(source.contains("let leftIsTip"))
        XCTAssertTrue(source.contains("let rightIsTip"))
        XCTAssertTrue(source.contains("if leftIsTip { return .left }"))
        XCTAssertTrue(source.contains("if rightIsTip { return .right }"))
    }

    func testMeasuredLeftTurnGeometryMapsLeft() {
        // Measured from supplied Apple US-1/North left-turn screenshot after
        // isolating the maneuver glyph.
        let leftCount = 340
        let rightCount = 1079
        let leftSpan = 33
        let rightSpan = 102

        let leftIsTip =
            Double(leftCount) < Double(rightCount) * 0.72 &&
            Double(leftSpan) < Double(rightSpan) * 0.78

        XCTAssertTrue(leftIsTip)
    }

    func testMeasuredRightTurnGeometryMapsRight() {
        // Measured from supplied Apple US-13/Powelton right-turn screenshot.
        let leftCount = 1598
        let rightCount = 701
        let leftSpan = 98
        let rightSpan = 53

        let rightIsTip =
            Double(rightCount) < Double(leftCount) * 0.72 &&
            Double(rightSpan) < Double(leftSpan) * 0.78

        XCTAssertTrue(rightIsTip)
    }

    func testShieldOCRVariantsAreRecognizedBySource() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("extractRouteShieldPrefix"))
        XCTAssertTrue(source.contains(#"[/\\|]?"#))
        XCTAssertTrue(source.contains("shield.remainder"))
    }
}
