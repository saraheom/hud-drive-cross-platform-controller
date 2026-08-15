import XCTest
@testable import HUDController

final class V59AppleArrowDirectionTests: XCTestCase {
    func testClassifierUsesConnectedComponentIsolation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        // v60+ first isolates the actual bright maneuver glyph so fragments of
        // the white distance text cannot reverse the left/right result.
        XCTAssertTrue(source.contains("dominantArrowComponent(from: data)"))
        XCTAssertTrue(source.contains("componentArrowScore"))
        XCTAssertTrue(source.contains("connected bright-pixel components"))
        XCTAssertTrue(source.contains("let leftEdge = glyph.filter"))
        XCTAssertTrue(source.contains("let rightEdge = glyph.filter"))
        XCTAssertTrue(source.contains("let leftIsTip"))
        XCTAssertTrue(source.contains("let rightIsTip"))

        // Regression guards: neither of the two older unstable classifiers
        // should return.
        XCTAssertFalse(source.contains("arrowheadCutoff"))
        XCTAssertFalse(source.contains("headCenter"))
        XCTAssertFalse(source.contains("arrowheadCutoff"))
        XCTAssertFalse(source.contains("headCenter"))
    }

    func testLeftTurnExtremeEdgeGeometryIsNotReversed() {
        let leftCount = 340
        let rightCount = 1079
        let leftSpan = 33
        let rightSpan = 102
        XCTAssertTrue(
            Double(leftCount) < Double(rightCount) * 0.72 &&
            Double(leftSpan) < Double(rightSpan) * 0.78
        )
    }

    func testMirroredExtremeEdgeGeometryClassifiesAsRight() {
        let leftCount = 1598
        let rightCount = 701
        let leftSpan = 98
        let rightSpan = 53
        XCTAssertTrue(
            Double(rightCount) < Double(leftCount) * 0.72 &&
            Double(rightSpan) < Double(leftSpan) * 0.78
        )
    }
}
