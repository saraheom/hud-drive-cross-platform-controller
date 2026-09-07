from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_root_replaces_trips_tab_with_ambient_and_promotes_trips_to_top_icon():
    root = read("ios/HUDController/UI/RootView.swift")
    assert "case ambient" in root
    assert "case logs" not in root
    assert '.tabItem { Label("Ambient", systemImage: "lightbulb.2.fill") }' in root
    assert 'accessibilityLabel: "My Trips"' in root
    assert 'icon: "clock.arrow.circlepath"' in root
    assert 'accessibilityLabel: "Settings"' in root
    assert 'icon: "gearshape.fill"' in root
    assert "LogsView(state: state)" in root
    assert root.index('accessibilityLabel: "My Trips"') < root.index('accessibilityLabel: "Settings"')
    for title in ("Navigation", "Music", "Ambient"):
        assert f'shortcut("{title}"' in root


def test_vehicle_keeps_speed_limit_source_while_ambient_owns_light_controls():
    vehicle = read("ios/HUDController/UI/VehicleView.swift")
    ambient = read("ios/HUDController/UI/AmbientLightingView.swift")
    assert 'Picker("Speed-limit source"' in vehicle
    assert "SPEED + SPEED LIMIT" in vehicle
    assert "AMBIENT OVERSPEED WARNING" not in vehicle
    assert "HUD AUTO-BRIGHTNESS" not in vehicle
    assert "AmbientLightingView(" not in vehicle
    assert "AMBIENT OVERSPEED WARNING" in ambient
    assert "HUD AUTO-BRIGHTNESS" in ambient
    assert "Use Center/BLEDOM power for HUD Auto Brightness" in ambient
    assert "Day warning brightness" in ambient
    assert "Night warning brightness" in ambient
    assert "speedEngine.speedLimitAvailableForWarning" in ambient


def test_experimental_replay_and_persistent_music_cards_are_hidden():
    nav26 = read("ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift")
    media = read("ios/HUDController/UI/MediaView.swift")
    assert "Recorded CarPlay lane replay" not in nav26
    assert "Send This Recorded Step" not in nav26
    assert 'Picker("Lane placement"' not in nav26
    assert "Persistent stock music renderer" not in media
    assert 'Button("Start Full")' not in media
    assert 'Button("Start Mini")' not in media
    assert "CarPlay Now Playing" in media


def test_color_labels_match_visible_swatch_names_without_changing_wire_palette():
    theme = read("ios/HUDController/Models/HudColorTheme.swift")
    dashboard = read("ios/HUDController/UI/DashboardView.swift")
    # User-observed first three physical swatches.
    assert 'case .red:     return "Blue"' in theme
    assert 'case .green:   return "Red"' in theme
    assert 'case .blue:    return "Green"' in theme
    # Raw historic enum names and exact firmware values stay untouched.
    assert 'case red = "Red"' in theme
    assert 'case green = "Green"' in theme
    assert 'case blue = "Blue"' in theme
    assert 'case .red:     return "25E6F5"' in theme
    assert 'case .green:   return "F2357B"' in theme
    assert 'case .blue:    return "25F553"' in theme
    assert "theme.displayName" in dashboard
    assert "theme.originalWireValue" not in dashboard


def test_descriptive_copy_uses_reusable_collapsible_component():
    theme = read("ios/HUDController/UI/HudTheme.swift")
    assert "struct HudDescription: View" in theme
    assert "@State private var isExpanded" in theme
    assert 'Text("Details")' in theme
    assert '"chevron.up" : "chevron.down"' in theme
    assert 'accessibilityLabel(isExpanded ? "Hide description" : "Show description")' in theme

    for rel in (
        "ios/HUDController/UI/DashboardView.swift",
        "ios/HUDController/UI/VehicleView.swift",
        "ios/HUDController/UI/MediaView.swift",
        "ios/HUDController/UI/AmbientLightingView.swift",
        "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift",
        "ios/HUDController/UI/HudSettingsView.swift",
        "ios/HUDController/UI/RouteGuidanceStatusCard.swift",
        "ios/HUDController/UI/NotificationSettingsCard.swift",
    ):
        assert "HudDescription(" in read(rel), rel


def test_show_current_turn_text_is_persisted_and_exposed_below_current_street():
    settings = read("ios/HUDController/Models/HudSettings.swift")
    app = read("ios/HUDController/App/AppState.swift")
    nav26 = read("ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift")
    assert "navigationShowCurrentTurnText" in settings
    assert 'HUD.Settings.navigationShowCurrentTurnText' in settings
    assert 'default: true' in settings
    assert "navigation.showCurrentTurnText = settings.navigationShowCurrentTurnText" in app
    assert 'Toggle("Show Current Turn Text"' in nav26
    assert nav26.index('Toggle("Show Current Street"') < nav26.index('Toggle("Show Current Turn Text"')


def test_turn_text_filter_blanks_only_wire_primary_text():
    nav = read("ios/HUDController/Navigation/HudNavigationController.swift")
    assert "var wireInstruction = instruction" in nav
    assert "if !showCurrentTurnText" in nav
    assert 'wireInstruction.primaryText = ""' in nav
    assert 'wireInstruction.streetName = ""' not in nav
    assert 'wireInstruction.distanceMeters = 0' not in nav
    assert 'wireInstruction.maneuver =' not in nav
    assert "HudCommands.maneuver(instruction)" in nav


def test_maneuver_wire_preserves_leading_blank_text_slot_and_trims_only_trailing_lines():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    block = commands[commands.index("static func maneuver"):commands.index("// MARK: - Firmware-native lane guidance")]
    assert "var textLines = [" in block
    assert "instruction.primaryText" in block
    assert "instruction.streetName" in block
    assert "instruction.currentStreet" in block
    assert "while textLines.last?.isEmpty == true" in block
    assert "textLines.removeLast()" in block
    assert 'joined(separator: "\\n")' in block
    assert ".filter { !$0.isEmpty }" not in block


def test_old_lane_probe_selection_is_migrated_to_stock_center_so_eta_is_safe():
    settings = read("ios/HUDController/Models/HudSettings.swift")
    assert "restoredLanePlacement" in settings
    assert "lanePlacementMode = .centerNative" in settings
    assert "restoredLanePlacement != .centerNative" in settings
    assert 'store.set(HudLanePlacementMode.centerNative.rawValue, forKey: "HUD.Settings.lanePlacementMode")' in settings
