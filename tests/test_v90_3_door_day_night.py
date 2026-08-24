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
    assert "roleIDs([.dashboard, .centerConsole])" in block
    assert "contains(where: { isLogicallyPowered($0) })" in block
    assert "Dashboard OR Center Console" in monitor


def test_startup_pulse_uses_day_night_target_for_door():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "vehicleTargetBrightness(for device: AmbientLightDevice, night: Bool)" in monitor
    assert "return doorTargetBrightness(night: night)" in monitor
    assert "let targets = Dictionary(uniqueKeysWithValues:" in monitor
    assert 'reason: "\\(label) final vehicle target", persist: true' in monitor


def test_mid_drive_headlights_dim_and_restore_door_automatically():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert 'reason: "headlights on → nighttime door brightness"' in monitor
    assert 'reason: "headlights off → daytime door brightness"' in monitor
    assert "transitionDoorBrightness(" in monitor
    assert "doorNightBrightness" in monitor
    assert "doorDayBrightness" in monitor


def test_door_transition_does_not_overwrite_generic_preferred_brightness():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("private func transitionDoorBrightness", 1)[1].split("private func fade(ids:", 1)[0]
    assert "applyRuntimeBrightness" in block
    assert ".brightness =" not in block
    assert "lastAppliedBrightness" not in block


def test_ui_exposes_two_door_brightness_settings_and_detector_rule():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert 'Text("Door day / night brightness")' in view
    assert 'title: "Daytime"' in view
    assert 'title: "Night"' in view
    assert "monitor.setDoorDayBrightness" in view
    assert "monitor.setDoorNightBrightness" in view
    assert "either the Dashboard light or Center Console/BLEDOM light is powered" in view
