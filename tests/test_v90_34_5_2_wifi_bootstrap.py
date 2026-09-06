from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()


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


def test_wifi_diagnostic_buttons_separate_stock_bootstrap_from_ap_pin_mode4_test():
    assert "Hold Cast Mode 5" in UI
    assert "Pin AP + Return HUD Mode 4" in UI
    start = APP.index("func returnHUDRendererKeepingWiFi")
    end = APP.index("func disableHUDWiFiExposure", start)
    block = APP[start:end]
    assert block.index("hudHotspotBaseband(is5G: true, forceEnable: true)") < block.index("HudCommands.kivicMode(4)")
    assert "softwareUpdate" not in APP[APP.index("func enableHUDWiFiExposure"):APP.index("enum NativeLaneTestPreset")]
