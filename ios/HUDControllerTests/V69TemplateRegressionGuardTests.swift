import XCTest
@testable import HUDController

final class V69TemplateRegressionGuardTests: XCTestCase {
    func testCurrentTemplatePipelineIsPresentWithoutPinningLegacyThresholds() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("bestShiftedIoU"))
        XCTAssertTrue(source.contains("leftTemplate"))
        XCTAssertTrue(source.contains("rightTemplate"))
        XCTAssertTrue(source.contains("straightTemplate"))
        XCTAssertTrue(source.contains("let margin = best.1 - second"))
    }
}
