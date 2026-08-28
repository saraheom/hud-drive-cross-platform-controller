from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_door_has_persisted_day_and_night_brightness_targets():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "var doorDayBrightness: Int" in monitor
    assert "var doorNightBrightness: Int" in monitor
    assert "HUD.Ambient.v90_3.doorDayBrightness" in monitor
    assert "HUD.Ambient.v90_3.doorNightBrightness" in monitor
    assert "setDoorDayBrightness" in monitor
    assert "setDoorNightBrightness" in monitor


def test_night_detector_is_redundant_dashboard_or_center_console():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("private func headlightPowerPresent()", 1)[1].split("private func doorTargetBrightness", 1)[0]
    assert "headlightPowerSessionActive" in block
    assert "startup" not in block.lower()


def test_mid_drive_headlight_state_only_changes_door_target():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    commit = monitor.split("private func commitConfirmedHeadlightPower", 1)[1].split("private func noteHeadlightPowerSeen", 1)[0]
    assert "applyCurrentDoorDayNightTarget" in commit
    assert "queuePowerUpBreath" not in commit


def test_door_transition_preserves_generic_preferred_brightness():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("private func applyCurrentDoorDayNightTarget", 1)[1].split("private func transitionDoorBrightness", 1)[0]
    assert "transitionBrightness(" in block
    assert "doorTargetBrightness" in block
    assert ".brightness =" not in block


def test_ui_exposes_two_door_brightness_settings_and_simple_rule():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert 'title: "Door daytime brightness"' in view
    assert 'title: "Door night brightness"' in view
    assert "monitor.setDoorDayBrightness" in view
    assert "monitor.setDoorNightBrightness" in view
    assert "Door brightness is independent from animation and engine-session detection" in view
