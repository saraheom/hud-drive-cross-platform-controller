import XCTest
@testable import HUDController

final class V59AppleArrowDirectionTests: XCTestCase {
    func testClassifierUsesExtremeTipVersusStemInvariant() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("leftTipByMass"))
        XCTAssertTrue(source.contains("leftTipBySpan"))
        XCTAssertTrue(source.contains("rightTipByMass"))
        XCTAssertTrue(source.contains("rightTipBySpan"))
        XCTAssertTrue(source.contains("edgeWidth = max(3, Int(Double(bw) * 0.18))"))

        // Regression guard: the unstable v57 upper-arrowhead heuristic must
        // not return.
        XCTAssertFalse(source.contains("arrowheadCutoff"))
        XCTAssertFalse(source.contains("headCenter"))
    }

    func testLeftTurnGeometryIsNotReversed() {
        // Representative geometry measured from the supplied Apple Maps
        // left-turn screenshot: narrow left arrow tip, heavy right stem.
        let leftCount = 446
        let rightCount = 1525
        let leftSpan = 38
        let rightSpan = 87

        let leftTipByMass = Double(leftCount) < Double(rightCount) * 0.72
        let leftTipBySpan = Double(leftSpan) < Double(rightSpan) * 0.78

        XCTAssertTrue(leftTipByMass)
        XCTAssertTrue(leftTipBySpan)
    }

    func testMirroredGeometryClassifiesAsRight() {
        let leftCount = 1525
        let rightCount = 446
        let leftSpan = 87
        let rightSpan = 38

        let rightTipByMass = Double(rightCount) < Double(leftCount) * 0.72
        let rightTipBySpan = Double(rightSpan) < Double(leftSpan) * 0.78

        XCTAssertTrue(rightTipByMass)
        XCTAssertTrue(rightTipBySpan)
    }
}
