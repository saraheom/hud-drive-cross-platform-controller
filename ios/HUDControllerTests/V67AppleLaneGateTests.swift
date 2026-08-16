import XCTest
@testable import HUDController

final class V67AppleLaneGateTests: XCTestCase {
    func testLaneClassifierRequiresMultipleComponents() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("guard components.count >= 3"))
        XCTAssertTrue(source.contains("connectedComponents(from: grayPixels)"))
        XCTAssertTrue(source.contains("thresholdedPixels(crop, minimum: 105)"))
        XCTAssertTrue(source.contains("thresholdedPixels(crop, minimum: 205)"))
    }

    func testNormalTemplatePathStillExistsAfterLaneGate() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("let scores: [(HudManeuver, Double)]"))
        XCTAssertTrue(source.contains("bestShiftedIoU(normalized, leftTemplate)"))
        XCTAssertTrue(source.contains("bestShiftedIoU(normalized, rightTemplate)"))
        XCTAssertTrue(source.contains("bestShiftedIoU(normalized, straightTemplate)"))
    }
}
