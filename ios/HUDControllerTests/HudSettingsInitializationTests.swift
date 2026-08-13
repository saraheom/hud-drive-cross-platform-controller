import XCTest
@testable import HUDController

final class HudSettingsInitializationTests: XCTestCase {
    @MainActor
    func testSettingsCanInitialize() {
        let settings = HudSettings()
        XCTAssertTrue((0...100).contains(settings.brightness))
        XCTAssertTrue(DashboardPreset.presets.contains(settings.selectedPreset))
    }

    func testInitializerDoesNotReadInstanceDefaultsBeforeInitialization() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HUDController/Models/HudSettings.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("let store = UserDefaults.standard"))
        XCTAssertFalse(source.contains("func bool(_ key: String, default fallback: Bool) -> Bool {\\n            defaults."))
        XCTAssertFalse(source.contains("func integer(_ key: String, default fallback: Int) -> Int {\\n            defaults."))
    }
}
