from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
SETTINGS = (ROOT / "ios/HUDController/Models/HudSettings.swift").read_text()
NAV = (ROOT / "ios/HUDController/Navigation/HudNavigationController.swift").read_text()
UI26 = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
COMMANDS = (ROOT / "ios/HUDController/Protocol/HudCommands.swift").read_text()


def test_navigation_presentation_persists_three_lane_modes_and_threshold():
    assert "enum HudLaneGuidanceMode" in SETTINGS
    assert "case nearTurn" in SETTINGS
    assert "case persistent" in SETTINGS
    assert "navigationShowCurrentStreet" in SETTINGS
    assert "laneGuidanceDistanceMiles" in SETTINGS
    assert "default: 0.5" in SETTINGS


def test_current_street_is_suppressed_only_on_wire_copy():
    assert "var wireInstruction = instruction" in NAV
    assert 'wireInstruction.currentStreet = ""' in NAV
    assert "let instruction = wireInstruction" in NAV
    assert "HudCommands.maneuver(instruction)" in NAV


def test_lane_policy_reasserts_stock_lane_packet_without_firmware_write():
    assert "laneGuidanceRefreshInterval" in APP
    assert ".milliseconds(1500)" in APP
    assert "setLaneGuidanceForCurrentManeuver" in APP
    assert "HudCommands.laneGuidance(activeLaneGuidance)" in APP
    assert "activeLaneDistanceMeters <= laneGuidanceThresholdMeters" in APP


def test_recorded_replay_is_retained_and_routes_through_policy():
    assert "Recorded CarPlay lane replay" in UI26
    assert "sendRecordedCarPlayLaneReplayStep" in APP
    start = APP.index("func sendRecordedCarPlayLaneReplayStep")
    block = APP[start:start + 1800]
    assert "setLaneGuidanceForCurrentManeuver" in block


def test_custom_app_uses_stock_softap_bootstrap_without_ota_start():
    assert "static func hudHotspotBaseband" in COMMANDS
    assert "static func kivicMode" in COMMANDS
    assert "HUD Wi-Fi / casting network" in UI26
    assert "Expose HUD Wi-Fi" in UI26
    assert "Pin AP + Return HUD Mode 4" in UI26
    start = APP.index("func enableHUDWiFiExposure")
    end = APP.index("func holdHUDWiFiCastingModeForDiagnostics", start)
    block = APP[start:end]
    assert "hudHotspotBaseband(is5G: true, forceEnable: false)" in block
    assert "HudCommands.kivicMode(5)" in block
    assert "HudCommands.kivicMode(4)" not in block
    assert ".milliseconds(5000)" in block
    assert "softwareUpdate" not in block
