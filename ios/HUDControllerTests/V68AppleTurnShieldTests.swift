import XCTest
@testable import HUDController

final class V68AppleTurnShieldTests: XCTestCase {
    func testTurnTemplateAcceptanceIsLessLikelyToCollapseToStraight() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("best.1 >= 0.38"))
        XCTAssertTrue(source.contains("margin >= 0.075"))
        XCTAssertTrue(source.contains("best.0 == .left || best.0 == .right"))
    }

    func testShieldRecoveryUsesMultipleUpscaledROIs() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("leftExpansions: [CGFloat] = [0.12, 0.17, 0.22, 0.27]"))
        XCTAssertTrue(source.contains("upscaleShieldCrop(crop, scale: 4)"))
        XCTAssertTrue(source.contains("request.minimumTextHeight = 0.025"))
        XCTAssertTrue(source.contains("request.topCandidates(10)") == false) // API is observation.topCandidates
        XCTAssertTrue(source.contains("observation.topCandidates(10)"))
    }
}
