import XCTest
@testable import HUDController

final class V87OriginalHUDColorThemeTests: XCTestCase {
    func testOriginalPaletteOrderAndNames() {
        XCTAssertEqual(
            HudColorTheme.allCases.map(\.rawValue),
            [
                "Red", "Green", "Blue", "Magenta", "Black",
                "Yellow", "Grey", "Cyan", "Ivory", "Maroon"
            ]
        )
    }

    func testOriginalRawColorMappings() {
        let expected: [HudColorTheme: String] = [
            .red: "25E6F5",
            .green: "F2357B",
            .blue: "25F553",
            .magenta: "4091F0",
            .black: "995EE5",
            .yellow: "D825F5",
            .grey: "1229F6",
            .cyan: "FFFFFF",
            .ivory: "F49238",
            .maroon: "F1F525"
        ]

        for (theme, rgb) in expected {
            XCTAssertEqual(theme.rgbHex, rgb)
            XCTAssertEqual(
                theme.originalWireValue,
                "#ff\(rgb.lowercased())"
            )
        }
    }

    func testBaseColorPacketUsesOriginalCommandAndUtfPayload() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let source = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Protocol/HudCommands.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("p1: 120"))
        XCTAssertTrue(source.contains("p2: 0"))
        XCTAssertTrue(
            source.contains(
                "HudProtocol.javaWriteUTF(theme.originalWireValue)"
            )
        )
    }

    func testColorPersistsAndRehydrates() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let settings = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/Models/HudSettings.swift"
            ),
            encoding: .utf8
        )
        let appState = try String(
            contentsOf: root.appendingPathComponent(
                "HUDController/App/AppState.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            settings.contains("HUD.Settings.colorTheme")
        )
        XCTAssertTrue(
            settings.contains("?? \"Red\"")
        )
        XCTAssertTrue(
            appState.contains("func applyColorTheme()")
        )
        XCTAssertGreaterThanOrEqual(
            appState.components(
                separatedBy: "applyColorTheme()"
            ).count - 1,
            2
        )
    }
}
