import XCTest
@testable import HUDController

final class V58ExperimentalMusicBindingTests: XCTestCase {
    func testExperimentalMediaControlsUseExplicitBindings() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/UI/MediaView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(source.contains("$state.settings.experimentalMusic"))
        XCTAssertTrue(source.contains("get: { state.settings.experimentalMusicPosition }"))
        XCTAssertTrue(source.contains("set: { state.settings.experimentalMusicPosition = $0 }"))
        XCTAssertTrue(source.contains("get: { state.settings.experimentalMusicMirror }"))
        XCTAssertTrue(source.contains("get: { state.settings.experimentalMusicTimeout }"))
        XCTAssertTrue(source.contains("get: { state.settings.experimentalMusicLines }"))
        XCTAssertTrue(source.contains("get: { state.settings.experimentalMusicMini }"))
    }
}
