from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()


def test_ios_cast_mode_bootstraps_before_ios_hud_mode_restore():
    start = APP.index("func enableHUDWiFiExposure()")
    end = APP.index("func holdHUDWiFiCastingModeForDiagnostics", start)
    block = APP[start:end]
    assert block.index("hudHotspotBaseband(is5G: false, forceEnable: true)") < block.index("HudCommands.kivicMode(5)")
    assert block.index("HudCommands.kivicMode(5)") < block.index("HudCommands.kivicMode(4)")
    assert ".milliseconds(1800)" in block


def test_disable_restores_ios_hud_mode_not_android_mode():
    start = APP.index("func disableHUDWiFiExposure")
    block = APP[start:start + 1800]
    assert "hudHotspotBaseband(is5G: false, forceEnable: false)" in block
    assert "HudCommands.kivicMode(4)" in block
    assert "HudCommands.kivicMode(0)" not in block


def test_wifi_diagnostic_buttons_allow_mode5_vs_mode4_ap_survival_test():
    assert "Hold Cast Mode 5" in UI
    assert "Return HUD Mode 4" in UI
    assert "softwareUpdate" not in APP[APP.index("func enableHUDWiFiExposure"):APP.index("enum NativeLaneTestPreset")]
