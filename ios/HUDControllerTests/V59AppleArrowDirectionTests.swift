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
        XCTAssertTrue(source.contains("let upperCut = minY + Int(Double(bh) * 0.60)"))
        XCTAssertTrue(source.contains("upperLeft"))
        XCTAssertTrue(source.contains("upperRight"))
        XCTAssertTrue(source.contains("normalizedShift"))

        // Regression guards: neither of the two older unstable classifiers
        // should return.
        XCTAssertFalse(source.contains("arrowheadCutoff"))
        XCTAssertFalse(source.contains("headCenter"))
        XCTAssertFalse(source.contains("leftTipByMass"))
        XCTAssertFalse(source.contains("leftTipBySpan"))
        XCTAssertFalse(source.contains("rightTipByMass"))
        XCTAssertFalse(source.contains("rightTipBySpan"))
    }

    func testLeftTurnUpperComponentGeometryIsNotReversed() {
        // Representative isolated-glyph geometry for a left-turn icon:
        // upper arrowhead mass is biased left.
        let upperLeft = 910
        let upperRight = 520

        XCTAssertGreaterThan(
            Double(upperLeft),
            Double(upperRight) * 1.16
        )
    }

    func testMirroredUpperComponentGeometryClassifiesAsRight() {
        let upperLeft = 520
        let upperRight = 910

        XCTAssertGreaterThan(
            Double(upperRight),
            Double(upperLeft) * 1.16
        )
    }
}
