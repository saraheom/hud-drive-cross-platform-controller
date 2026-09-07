import XCTest
@testable import HUDController

final class V90349PersistentMusicAndUICleanupTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testPersistentMusicBackendStillUsesExistingNativeRendererOnly() throws {
        let app = try source("HUDController/App/AppState.swift")
        guard let start = app.range(of: "// MARK: - Persistent stock music renderer experiment")?.lowerBound,
              let end = app.range(of: "func sendNativeMusicMiniTest", range: start..<app.endIndex)?.lowerBound else {
            XCTFail("persistent music source range missing")
            return
        }
        let section = String(app[start..<end])
        XCTAssertTrue(app.contains("private let persistentMusicRefreshInterval: Duration = .seconds(5)"))
        XCTAssertTrue(section.contains("Task.sleep(for: self.persistentMusicRefreshInterval)"))
        XCTAssertTrue(section.contains("HudCommands.musicNotification"))
        XCTAssertTrue(section.contains("HudCommands.widgetsMiniState(true)"))
        XCTAssertFalse(section.contains("adb."))
        XCTAssertFalse(section.contains("/data/"))
        XCTAssertFalse(section.contains("/system/"))
    }

    func testIOS26NavigationUIHasNoExperimentalDiagnosticCards() throws {
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        let settingsUI = try source("HUDController/UI/HudSettingsView.swift")
        XCTAssertFalse(ui.contains("Ambient-light test build"))
        XCTAssertFalse(ui.contains("Manual navigation diagnostics"))
        XCTAssertFalse(ui.contains("Firmware-native lane guidance"))
        XCTAssertFalse(ui.contains("Recorded CarPlay lane replay"))
        XCTAssertTrue(ui.contains("Navigation presentation"))
        XCTAssertFalse(ui.contains("HUD Firmware Maintenance"))
        XCTAssertTrue(settingsUI.contains("HUD Firmware Maintenance"))
    }

    func testMediaUIHidesExperimentalPersistentRendererControls() throws {
        let ui = try source("HUDController/UI/MediaView.swift")
        XCTAssertFalse(ui.contains("Persistent stock music renderer"))
        XCTAssertFalse(ui.contains("Start Full"))
        XCTAssertFalse(ui.contains("Start Mini"))
        XCTAssertFalse(ui.contains("Stop + Restore Normal HUD"))
        XCTAssertTrue(ui.contains("CarPlay Now Playing"))
    }
}
