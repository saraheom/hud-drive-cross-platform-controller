import XCTest
@testable import HUDController

final class V66AppleTemplateClassifierTests: XCTestCase {
    func testAppleSimpleArrowUsesTemplateMatching() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Navigation/GoogleMapsOCRParser.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("leftTemplate"))
        XCTAssertTrue(source.contains("rightTemplate"))
        XCTAssertTrue(source.contains("straightTemplate"))
        XCTAssertTrue(source.contains("bestShiftedIoU"))
        XCTAssertTrue(source.contains("normalizeGlyph"))

        // v68 keeps template matching but uses different acceptance thresholds
        // for genuine turn candidates versus Straight.
        XCTAssertTrue(source.contains("best.0 == .left || best.0 == .right"))
        XCTAssertTrue(source.contains("best.1 >= 0.38"))
        XCTAssertTrue(source.contains("margin >= 0.075"))
        XCTAssertTrue(source.contains("best.1 >= 0.56"))
        XCTAssertTrue(source.contains("margin >= 0.12"))

        // Old geometric heuristics must remain absent.
        XCTAssertFalse(source.contains("centroidShift"))
        XCTAssertFalse(source.contains("leftIsTip"))
        XCTAssertFalse(source.contains("rightIsTip"))
    }

    func testExperimentalPersistentMusicUIIsRemoved() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let media = try String(
            contentsOf: root.appendingPathComponent("HUDController/UI/MediaView.swift"),
            encoding: .utf8
        )
        let state = try String(
            contentsOf: root.appendingPathComponent("HUDController/App/AppState.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(media.contains("Experimental HUD Music Layout"))
        XCTAssertFalse(media.contains("experimentalMusic"))
        XCTAssertFalse(state.contains("sendExperimentalMusic"))
        XCTAssertFalse(state.contains("experimentalMusicMirror"))
    }
}
