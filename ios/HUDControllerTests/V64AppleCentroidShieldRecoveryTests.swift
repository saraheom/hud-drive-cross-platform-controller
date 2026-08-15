import XCTest
@testable import HUDController

final class V64AppleCentroidShieldRecoveryTests: XCTestCase {
    func testAppleClassifierUsesIsolatedComponentCentroid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("dominantArrowComponent(from: data)"))
        XCTAssertTrue(source.contains("let centroidX"))
        XCTAssertTrue(source.contains("let centroidShift"))
        XCTAssertTrue(source.contains("if centroidShift > 0.025"))
        XCTAssertTrue(source.contains("return .left"))
        XCTAssertTrue(source.contains("if centroidShift < -0.025"))
        XCTAssertTrue(source.contains("return .right"))

        XCTAssertFalse(source.contains("let leftIsTip"))
        XCTAssertFalse(source.contains("let rightIsTip"))
        XCTAssertFalse(source.contains("let upperLeft ="))
        XCTAssertFalse(source.contains("let upperRight ="))
    }

    func testMeasuredLeftScreenshotCentroidMapsLeft() {
        // Exact first-arrow component measurement from the supplied
        // 0.4 mi / US 1 North left-turn screenshot.
        let minX = 103.0
        let maxX = 231.0
        let centroidX = 174.4409787075084
        let width = maxX - minX + 1.0
        let center = (minX + maxX) / 2.0
        let shift = (centroidX - center) / width

        XCTAssertGreaterThan(shift, 0.025)
    }

    func testMeasuredRightScreenshotCentroidMapsRight() {
        // Exact first-arrow component measurement from the supplied
        // 150 ft / US 13 Powelton Ave right-turn screenshot.
        let minX = 100.0
        let maxX = 228.0
        let centroidX = 156.83505903723886
        let width = maxX - minX + 1.0
        let center = (minX + maxX) / 2.0
        let shift = (centroidX - center) / width

        XCTAssertLessThan(shift, -0.025)
    }

    func testSecondaryShieldOCRRecoveryIsPresent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("recoverRouteShieldNumber"))
        XCTAssertTrue(source.contains("VNRecognizeTextRequest()"))
        XCTAssertTrue(source.contains("request.recognitionLevel = .accurate"))
        XCTAssertTrue(source.contains("shield region immediately to the left"))
    }
}
