import XCTest
@testable import HUDController

final class V61AppleComponentRegressionTests: XCTestCase {
    func testComponentIsolationPrecedesDirectionClassification() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        guard let isolate = source.range(of: "dominantArrowComponent(from: data)"),
              let direction = source.range(of: "let leftEdge = glyph.filter")
        else {
            XCTFail("Expected Apple component-isolation pipeline not found")
            return
        }

        XCTAssertLessThan(isolate.lowerBound, direction.lowerBound)
    }
}
