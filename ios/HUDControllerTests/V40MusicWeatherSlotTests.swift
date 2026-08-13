import XCTest
@testable import HUDController

final class V40MusicWeatherSlotTests: XCTestCase {
    func testWeatherIsNoLongerRepurposedAsMusic() {
        XCTAssertEqual(HudSideWidget.weather.rawValue, "Weather")
        XCTAssertEqual(HudSideWidget.weather.displayName, "Weather")
    }

    func testUndocumentedMusicWidgetTokenIsAbsent() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Models/HudDashboardWidget.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("spotifyMusicExperimental"))
        XCTAssertFalse(source.contains("isMusicDisplaySlot"))
    }
}
