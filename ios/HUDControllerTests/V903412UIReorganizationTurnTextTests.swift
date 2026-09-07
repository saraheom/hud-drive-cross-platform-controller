import XCTest
@testable import HUDController

final class V903412UIReorganizationTurnTextTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testRootPromotesTripsAndSettingsAndUsesAmbientBottomTab() throws {
        let root = try source("HUDController/UI/RootView.swift")
        XCTAssertTrue(root.contains("case ambient"))
        XCTAssertFalse(root.contains("case logs"))
        XCTAssertTrue(root.contains("AmbientLightingView("))
        XCTAssertTrue(root.contains("accessibilityLabel: \"My Trips\""))
        XCTAssertTrue(root.contains("icon: \"clock.arrow.circlepath\""))
        XCTAssertTrue(root.contains("accessibilityLabel: \"Settings\""))
        XCTAssertTrue(root.contains("icon: \"gearshape.fill\""))
        XCTAssertTrue(root.contains("LogsView(state: state)"))
    }

    func testAmbientOwnsAllLightSpecificVehicleControls() throws {
        let vehicle = try source("HUDController/UI/VehicleView.swift")
        let ambient = try source("HUDController/UI/AmbientLightingView.swift")
        XCTAssertTrue(vehicle.contains("Picker(\"Speed-limit source\""))
        XCTAssertFalse(vehicle.contains("AMBIENT OVERSPEED WARNING"))
        XCTAssertFalse(vehicle.contains("HUD AUTO-BRIGHTNESS"))
        XCTAssertTrue(ambient.contains("AMBIENT OVERSPEED WARNING"))
        XCTAssertTrue(ambient.contains("HUD AUTO-BRIGHTNESS"))
        XCTAssertTrue(ambient.contains("Day warning brightness"))
        XCTAssertTrue(ambient.contains("Night warning brightness"))
    }

    func testExperimentalCardsAreNoLongerExposed() throws {
        let nav = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        let media = try source("HUDController/UI/MediaView.swift")
        XCTAssertFalse(nav.contains("Recorded CarPlay lane replay"))
        XCTAssertFalse(nav.contains("Picker(\"Lane placement\""))
        XCTAssertFalse(media.contains("Persistent stock music renderer"))
        XCTAssertFalse(media.contains("Start Full"))
        XCTAssertFalse(media.contains("Start Mini"))
    }

    func testVisibleColorNamesAreSeparatedFromOriginalWireIdentity() throws {
        XCTAssertEqual(HudColorTheme.red.displayName, "Blue")
        XCTAssertEqual(HudColorTheme.green.displayName, "Red")
        XCTAssertEqual(HudColorTheme.blue.displayName, "Green")
        XCTAssertEqual(HudColorTheme.red.rawValue, "Red")
        XCTAssertEqual(HudColorTheme.red.originalWireValue, "#ff25e6f5")
        XCTAssertEqual(HudColorTheme.green.originalWireValue, "#fff2357b")
        XCTAssertEqual(HudColorTheme.blue.originalWireValue, "#ff25f553")
    }

    func testTurnTextTogglePersistsAndFiltersOnlyWireCopy() throws {
        let settings = try source("HUDController/Models/HudSettings.swift")
        let nav = try source("HUDController/Navigation/HudNavigationController.swift")
        let ui = try source("HUDController/AmbientTest/HudNavigationViewIOS26.swift")
        XCTAssertTrue(settings.contains("navigationShowCurrentTurnText"))
        XCTAssertTrue(settings.contains("HUD.Settings.navigationShowCurrentTurnText"))
        XCTAssertTrue(ui.contains("Toggle(\"Show Current Turn Text\""))
        XCTAssertTrue(nav.contains("if !showCurrentTurnText"))
        XCTAssertTrue(nav.contains("wireInstruction.primaryText = \"\""))
        XCTAssertFalse(nav.contains("wireInstruction.streetName = \"\"\n        }\n        if !showCurrentTurnText"))
    }

    func testHiddenTurnTextKeepsTheFirstTextSlotBlank() throws {
        var instruction = NavigationInstruction(
            maneuver: .right,
            distanceMeters: 120,
            primaryText: "",
            streetName: "Market St",
            currentStreet: "Broad St"
        )
        instruction.exitNumber = nil
        let body = try XCTUnwrap(HudProtocol.unescape(HudCommands.maneuver(instruction)))
        XCTAssertEqual(body[0], 2)
        XCTAssertEqual(body[1], 100)
        XCTAssertEqual(body[2], 1)

        let utfLength = Int(body[3]) << 8 | Int(body[4])
        let textBytes = body.subdata(in: 5..<(5 + utfLength))
        let text = String(data: textBytes, encoding: .utf8)
        XCTAssertEqual(text, "\nMarket St\nBroad St")
    }

    func testDescriptionsAreReusableAndCollapsible() throws {
        let theme = try source("HUDController/UI/HudTheme.swift")
        XCTAssertTrue(theme.contains("struct HudDescription: View"))
        XCTAssertTrue(theme.contains("@State private var isExpanded"))
        XCTAssertTrue(theme.contains("chevron.up"))
        XCTAssertTrue(theme.contains("chevron.down"))
        XCTAssertTrue(theme.contains("Hide description"))
        XCTAssertTrue(theme.contains("Show description"))
    }
}
