from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_five_preset_slots_exist_for_devices_and_groups():
    model = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "static let defaultPresets" in model
    assert model.count("var presetColors: [AmbientRGB]?") >= 2
    assert "resolvedPresetColors" in model
    assert "setDevicePresetColor" in monitor
    assert "setGroupPresetColor" in monitor
    assert "ForEach(0..<5" in view
    assert "long-press to save" in view


def test_manual_device_and_group_brightness_use_same_smooth_transition():
    src = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    device = src.split("func setBrightness(_ id: UUID", 1)[1].split("func setStartupAnimationEnabled", 1)[0]
    group = src.split("func setGroupBrightness(_ groupID: UUID", 1)[1].split("private func updateDevice", 1)[0]
    assert "transitionBrightness(" in device
    assert "brightnessTransitionSeconds" in device
    assert "transitionBrightness(" in group
    assert "brightnessTransitionSeconds" in group


def test_breath_is_only_powerup_animation_and_uses_requested_path():
    src = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert "breathCycles" in src and "max(2, min(5" in src
    assert "breathDurationSeconds" in src and "max(1.0, min(15.0" in src
    assert "case 0:" in src and "from = Double(clampedStart); to = 0" in src
    assert "case 1:" in src and "from = 0; to = 100" in src
    assert "cycleIndex == safeCycles - 1 ? clampedReturn : clampedStart" in src
    assert "Synchronized breath begin" in src
    assert "perCycleDuration = max(1.0, min(15.0, breathDurationSeconds))" in src
    assert "totalDuration = perCycleDuration * Double(cycles)" in src
    assert "Breath duration / cycle" in view
    assert "Startup pulse" not in view
    assert "Preview Breath" in view


def test_breath_and_group_fades_share_timeline_for_visual_sync():
    src = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "activeBreathIDs" in src
    assert "Joined active synchronized breath" in src
    assert "try? await Task.sleep(for: .seconds(0.35))" in src
    assert "let frameInterval = 0.05" in src
    assert "targets: Dictionary(uniqueKeysWithValues: steady.map" in src


def test_nearby_ble_list_is_hidden_but_scanning_remains():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert 'section("NEARBY BLE DEVICES")' not in view
    assert "nearby-device list is hidden" in view
    assert "func scanNow()" in monitor
    assert "startScanning()" in monitor


def test_persistent_quick_shortcuts_cover_navigation_music_ambient_except_logs():
    root = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()
    app = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
    vehicle = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
    assert "QuickShortcutBar" in root
    assert 'shortcut("Navigation"' in root
    assert 'shortcut("Music"' in root
    assert 'shortcut("Ambient"' in root
    assert "selectedTab != .logs" in root
    assert "state.quickStartNavigation()" in root
    assert "state.quickReconnectSpotify()" in root
    assert "state.ambientLight.requestPairedLightsFocus()" in root
    assert "navigation.navigationOn()" in app
    assert "capture.presentFullDisplayPicker()" in app
    assert "spotify.connectOrAuthorize()" in app
    assert "spotify.openSpotifyAndResumeConnection()" in app
    assert 'path = [.ambient(focusPairedLights: true)]' in vehicle
    assert '.id("pairedLights")' in (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()


def test_door_day_night_sliders_commit_after_drag_instead_of_restarting_fade_per_tick():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert "@State private var doorDayDraft" in view
    assert "@State private var doorNightDraft" in view
    assert "if !editing { monitor.setDoorDayBrightness" in view
    assert "if !editing { monitor.setDoorNightBrightness" in view


def test_manual_power_on_uses_same_breath_path_when_animation_enabled():
    src = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = src.split("func setPower(_ id: UUID, on: Bool)", 1)[1].split("func setColor", 1)[0]
    assert "startupAnimationEnabled" in block
    assert "queuePowerUpBreath(id, force: true)" in block


def test_breath_uses_actual_start_and_only_last_cycle_can_return_to_changed_target():
    src = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "activeBreathStartBrightness[id] = device.runtimeBrightness" in src
    assert "activeBreathReturnBrightness[id] = device.runtimeBrightness" in src
    assert "cycleIndex == safeCycles - 1 ? clampedReturn : clampedStart" in src
    assert "activeBreathReturnBrightness[id] = clamped" in src
    assert "Door breath final target updated" in src
