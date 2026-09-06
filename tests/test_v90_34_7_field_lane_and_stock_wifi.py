from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
ROUTE = (ROOT / "ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift").read_text()
UI = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()


def _block(text: str, start: str, end: str) -> str:
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def test_field_fix_consumes_v88_event_selector_not_event_as_maneuver_index():
    block = _block(APP, "private func receiveResolvedV88LaneGuidance", "private func receiveLegacyV87LaneGuidance")
    assert "state.laneGuidanceIndex" in block
    assert "state.laneGuidanceEventIndex" in block
    assert "liveLaneCacheByManeuver" not in block
    assert "state.laneManeuverIndex" not in block


def test_route_maneuver_send_is_followed_by_lane_reassert_callback():
    send = ROUTE.index("navigation.sendCurrent(owner: .carPlayAdapter)")
    cb = ROUTE.index("onManeuverDelivered?", send)
    signature = ROUTE.index("lastDeliveredSignature = visibleSignature", cb)
    assert send < cb < signature
    reassert = _block(APP, "private func reassertLiveLaneAfterManeuverDelivery", "private func updateActiveLaneDistanceMeters")
    assert "activeManeuver == maneuverIndex" in reassert
    assert 'sendActiveLaneGuidance(label: "Lane policy → post-maneuver reassert")' in reassert


def test_settings_change_sends_maneuver_before_lane_policy_reassert():
    block = _block(APP, "func applyNavigationPresentationSettings", "private func shouldDisplayActiveLanes")
    assert block.index("navigation.sendCurrent") < block.index("reevaluateActiveLaneGuidance")


def test_near_turn_uses_live_distance_and_does_not_require_stock_showing_flag_after_activation():
    gate = _block(APP, "private func shouldDisplayActiveLanes", "private func reevaluateActiveLaneGuidance")
    assert "activeLaneDistanceMeters <= laneGuidanceThresholdMeters" in gate
    assert "laneGuidanceShowing" not in gate
    resolved = _block(APP, "private func receiveResolvedV88LaneGuidance", "private func receiveLegacyV87LaneGuidance")
    assert "CARPLAY LANE LATCH" in resolved
    assert "keeping event" in resolved


def test_stock_wifi_bootstrap_matches_captured_original_app_and_does_not_auto_return():
    block = _block(APP, "func enableHUDWiFiExposure", "func holdHUDWiFiCastingModeForDiagnostics")
    hotspot = block.index("hudHotspotBaseband(is5G: true, forceEnable: false)")
    mode5 = block.index("HudCommands.kivicMode(5)")
    wait = block.index(".milliseconds(5000)")
    assert hotspot < mode5 < wait
    assert "HudCommands.kivicMode(4)" not in block
    assert "softwareUpdate" not in block


def test_failed_pin_ap_experiment_is_removed_and_maintenance_uses_stock_mode5():
    assert "returnHUDRendererKeepingWiFi" not in APP
    assert "hudHotspotBaseband(is5G: true, forceEnable: true)" not in APP
    assert "Pin AP + Return HUD Mode 4" not in UI
    maintenance = _block(APP, "func startFirmwareMaintenance", "func reconnectFirmwareMaintenanceADB")
    assert "enableHUDWiFiExposure()" in maintenance
    assert "Start Firmware Maintenance" in UI


def test_no_firmware_writer_was_added_to_this_wifi_lane_build():
    assert "HudCommands.softwareUpdate" not in APP
    wifi = _block(APP, "func enableHUDWiFiExposure", "enum NativeLaneTestPreset")
    assert "URLSession" not in wifi
    assert "NWConnection" not in wifi
