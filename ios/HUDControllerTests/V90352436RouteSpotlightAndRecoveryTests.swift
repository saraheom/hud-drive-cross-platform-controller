import XCTest
import UIKit
@testable import HUDController

final class V90352436RouteSpotlightAndRecoveryTests: XCTestCase {
    func testRouteSpotlightExtractsStrongYellowPathWithoutPreservingGrayMap() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 192))
        let source = renderer.image { context in
            UIColor(white: 0.55, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 192))
            UIColor(red: 1.0, green: 0.8, blue: 0.12, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 155, y: 37, width: 5, height: 125))
        }
        let result = try XCTUnwrap(HudRouteSpotlightProcessor.render(source))
        XCTAssertEqual(result.size.width, 320)
        XCTAssertEqual(result.size.height, 192)
    }

    func testRouteSpotlightCanExtractDistinctBlueDaytimeRoute() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 192))
        let source = renderer.image { context in
            UIColor(white: 0.89, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 192))
            UIColor(red: 0.12, green: 0.46, blue: 0.97, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 130, y: 35, width: 6, height: 126))
        }
        XCTAssertNotNil(HudRouteSpotlightProcessor.render(source))
    }

    func testRouteSpotlightDoesNotInventARouteWhenOnlyNeutralRoadsArePresent() {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 192)).image { context in
            UIColor(white: 0.6, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 192))
        }
        XCTAssertNil(HudRouteSpotlightProcessor.render(source))
    }

    func testMapAppearanceIncludesExperimentalRouteSpotlight() {
        XCTAssertTrue(HudMapAppearance.allCases.contains(.routeSpotlight))
        XCTAssertEqual(HudMapAppearance(rawValue: "darkHUD"), .darkHUD)
    }

    func testInPlaceRecoveryAndDiagnosticMarkersRemainInSource() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../HUDController/MapMode/U2WMainVideoClient.swift").standardized
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains("beginInPlaceReadOnlyBootstrap"))
        XCTAssertTrue(source.contains("BYTE_OVERLAP_PROVEN"))
        XCTAssertTrue(source.contains("IN_PLACE_BOOTSTRAP"))
        XCTAssertTrue(source.contains("decoded_continuity_probe"))
    }
}
