from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
SETTINGS_UI = (ROOT / "ios/HUDController/UI/HudSettingsView.swift").read_text()


def test_ios_cast_mode_matches_captured_stock_5ghz_sequence_and_holds_mode5():
    start = APP.index("func enableHUDWiFiExposure()")
    end = APP.index("func holdHUDWiFiCastingModeForDiagnostics", start)
    block = APP[start:end]
    hotspot = block.index("hudHotspotBaseband(is5G: true, forceEnable: false)")
    cast = block.index("HudCommands.kivicMode(5)")
    assert hotspot < cast
    assert ".milliseconds(5000)" in block
    # Physical stock log does not return to mode 4 during SoftAP bootstrap.
    assert "HudCommands.kivicMode(4)" not in block
    assert "softwareUpdate" not in block
    assert "URLSession" not in block


def test_disable_matches_captured_stock_off_transition():
    start = APP.index("func disableHUDWiFiExposure")
    block = APP[start:start + 1800]
    assert "hudHotspotBaseband(is5G: true, forceEnable: false)" in block
    assert "HudCommands.kivicMode(4)" in block
    assert "HudCommands.kivicMode(0)" not in block


def test_failed_ap_pin_experiment_is_removed_from_current_ui_and_runtime():
    assert "Pin AP + Return HUD Mode 4" not in UI
    assert "returnHUDRendererKeepingWiFi" not in APP
    assert "hudHotspotBaseband(is5G: true, forceEnable: true)" not in APP
    assert "Start Firmware Maintenance" not in UI
    assert "Start Firmware Maintenance" in SETTINGS_UI
    assert "softwareUpdate" not in APP[APP.index("func enableHUDWiFiExposure"):APP.index("enum NativeLaneTestPreset")]
