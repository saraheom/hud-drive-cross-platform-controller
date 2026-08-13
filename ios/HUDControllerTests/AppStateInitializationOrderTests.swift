import XCTest
@testable import HUDController

final class AppStateInitializationOrderTests: XCTestCase {
    func testTextProbeInitializedBeforeSpotifyCallback() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/App/AppState.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let probeRange = source.range(of: "self.textProbe = HudTextRendererProbe"),
              let callbackRange = source.range(of: "spotify.onTrackChanged") else {
            XCTFail("Expected initialization markers not found")
            return
        }

        XCTAssertLessThan(
            source.distance(from: source.startIndex, to: probeRange.lowerBound),
            source.distance(from: source.startIndex, to: callbackRange.lowerBound)
        )
    }
}
