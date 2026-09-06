from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
ROUTE = (ROOT / "ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift").read_text()
UI = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()


def test_google_maps_cursor_wobble_no_longer_clears_lane_cache():
    assert "no cache reset on cursor wobble" in APP
    cursor = APP[APP.index("Google Maps can transiently"):APP.index("if state.schemaVersion >= 2")]
    assert "clearLaneGuidancePolicy" not in cursor
    assert "liveLaneCacheByManeuver.removeAll()" not in cursor


def test_v88_hidden_selector_zero_does_not_replace_persistent_latched_event():
    block = APP[APP.index("private func receiveResolvedV88LaneGuidance"):APP.index("private func receiveLegacyV87LaneGuidance")]
    assert "if state.laneGuidanceShowing" in block
    assert "hidden selector must never" in block
    assert "showing=0 selector=" in block
    assert "keeping event=" in block
    assert "live lane maneuver completed" in block


def test_stock_wifi_sequence_uses_physical_capture_parameters():
    block = APP[APP.index("func enableHUDWiFiExposure"):APP.index("func holdHUDWiFiCastingModeForDiagnostics")]
    assert "hudHotspotBaseband(is5G: true, forceEnable: false)" in block
    assert "HudCommands.kivicMode(5)" in block
    assert ".milliseconds(5000)" in block
    assert "HudCommands.kivicMode(4)" not in block
    assert "Starting stock 5-GHz HUDWAY AP" in block


def test_failed_ap_pin_mode4_experiment_is_retired_after_physical_test():
    assert "returnHUDRendererKeepingWiFi" not in APP
    assert "hudHotspotBaseband(is5G: true, forceEnable: true)" not in APP
    assert "Pin AP + Return HUD Mode 4" not in UI
    assert "Start Firmware Maintenance" in UI


def test_v88_json_fields_are_optional_for_v87_compatibility():
    assert "var version: Int" in ROUTE
    assert "var laneGuidanceIndex: Int?" in ROUTE
    assert "var guidanceEventIndex: Int?" in ROUTE
    assert "var maneuverIndex: Int?" in ROUTE
