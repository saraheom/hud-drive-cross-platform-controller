from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMANDS = (ROOT / "ios/HUDController/Protocol/HudCommands.swift").read_text()
PROTOCOL = (ROOT / "ios/HUDController/Protocol/HudProtocol.swift").read_text()
SETTINGS = (ROOT / "ios/HUDController/Models/HudSettings.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
ROOT_VIEW = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()
SETTINGS_UI = (ROOT / "ios/HUDController/UI/HudSettingsView.swift").read_text()
NAV26 = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
NAV = (ROOT / "ios/HUDController/UI/HudNavigationView.swift").read_text()


def test_original_hudway_scale_and_perspective_packets_are_float32_only():
    assert "static func float32(_ value: Float)" in PROTOCOL
    assert "value.bitPattern.bigEndian" in PROTOCOL

    layout = COMMANDS[COMMANDS.index("static func layoutSize"):COMMANDS.index("static func keyStone")]
    assert "p1: 14" in layout
    assert "p2: 0" in layout
    assert "HudProtocol.float32(size)" in layout

    keystone = COMMANDS[COMMANDS.index("static func keyStone"):COMMANDS.index("// MARK: - HUD Wi-Fi")]
    assert "p1: 3" in keystone
    assert "p2: 0" in keystone
    assert "HudProtocol.float32(value)" in keystone


def test_original_slider_ranges_are_persisted_and_mapped_exactly():
    assert "displayScaleAdjustment" in SETTINGS
    assert "displayPerspectiveAdjustment" in SETTINGS
    assert "* 0.2 / 100.0" in SETTINGS
    assert "* 0.1 / 100.0" in SETTINGS
    assert 'default: 0' in SETTINGS
    assert "applyDisplayCalibration()" in APP
    assert APP.count("applyDisplayCalibration()") >= 3  # declaration + phase 2 + phase 3


def test_display_changes_are_ble_only_and_debounced():
    start = APP.index("// MARK: - Original HUDWAY display calibration")
    end = APP.index("func applyColorTheme()", start)
    block = APP[start:end]
    assert ".milliseconds(90)" in block
    assert "HudCommands.layoutSize" in block
    assert "HudCommands.keyStone" in block
    for forbidden in ("adb.", "/data/", "/system/", "softwareUpdate", "remount"):
        assert forbidden not in block


def test_top_right_settings_gear_opens_new_settings_page():
    assert 'icon: "gearshape.fill"' in ROOT_VIEW
    assert 'accessibilityLabel: "Settings"' in ROOT_VIEW
    assert "showSettings = true" in ROOT_VIEW
    assert "HudSettingsView(state: state)" in ROOT_VIEW
    assert 'navigationTitle("Settings")' in SETTINGS_UI


def test_display_and_firmware_blocks_are_moved_into_settings():
    assert "Original HUDWAY Scale + Perspective" in SETTINGS_UI
    assert "HUD Firmware Maintenance" in SETTINGS_UI
    assert "Start Firmware Maintenance" in SETTINGS_UI
    assert "Select Video or bootanimation.zip" in SETTINGS_UI
    assert "HUD Firmware Maintenance" not in NAV26
    assert "HUD Firmware Maintenance" not in NAV


def test_per_widget_research_does_not_invent_an_unverified_wire_command():
    assert "Per-widget scale / perspective" in SETTINGS_UI
    assert "no left/center/right widget identifier" in SETTINGS_UI
    # The two proven calibration packets accept only one Float and no slot/widget parameter.
    layout_sig = COMMANDS[COMMANDS.index("static func layoutSize"):COMMANDS.index("static func keyStone")]
    key_sig = COMMANDS[COMMANDS.index("static func keyStone"):COMMANDS.index("// MARK: - HUD Wi-Fi")]
    for block in (layout_sig, key_sig):
        assert "widget" not in block.lower()
        assert "left" not in block.lower()
        assert "center" not in block.lower()
        assert "right" not in block.lower()
