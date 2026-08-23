from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_bledim2_cb01_packet_profile_and_fff1_control_path():
    model = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "static let fff1" in model
    assert "0x7E, 0xFF, 0x04" in model
    assert "0x7E, 0xFF, 0x05, 0x03" in model
    assert "0x7E, 0xFF, 0x01" in model
    assert "isBLEDIMWriteCharacteristic" in monitor
    assert "BLEDIM2 FFF0/FFF1 experimental" in monitor


def test_vehicle_roles_match_physical_test_devices():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert 'hasPrefix("FBD8C9A0-")' in monitor
    assert 'return .door' in monitor
    assert 'hasPrefix("7A3B5F81-")' in monitor
    assert 'return .dashboard' in monitor
    assert 'hasPrefix("51FA23D6-")' in monitor
    assert 'return .centerConsole' in monitor


def test_shutdown_zero_is_runtime_state_not_preferred_brightness():
    model = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "var lastAppliedBrightness: Int?" in model
    assert "var brightness: Int" in model
    assert 'applyRuntimeBrightness(id, percent: 0, reason: "vehicle shutdown final", persist: true)' in monitor
    assert "$0.brightness = 0" not in monitor
    assert "preferred brightness preserved" in monitor


def test_automation_classifies_day_night_and_coalesces_headlight_join():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "beginVehicleStartupClassification" in monitor
    assert "finishVehicleStartupClassification" in monitor
    assert "Night startup classified" in monitor
    assert "Day startup classified" in monitor
    assert "scheduleHeadlightJoinFade" in monitor
    assert "Headlight OFF→ON" in monitor


def test_engine_power_uses_hud_and_obd_with_debounced_automatic_shutdown():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    appstate = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
    obd = (ROOT / "ios/HUDController/Vehicle/HudOBDController.swift").read_text()
    assert "func hudTransportPowerSignal(_ present: Bool)" in monitor
    assert "func obdPowerSignal(_ present: Bool)" in monitor
    assert "scheduleEnginePowerOffConfirmation" in monitor
    assert "directOBDWitnessProven" in monitor
    assert 'performVehicleShutdownFade(trigger: "engine power OFF")' in monitor
    assert "self.ambientLight.hudTransportPowerSignal(true)" in appstate
    assert "self.ambientLight.hudTransportPowerSignal(false)" in appstate
    assert "!self.bluetooth.userDisconnectRequested" in appstate
    assert "var onConnectionChanged: ((Bool) -> Void)?" in obd
    assert "engineRPM >" not in monitor


def test_stock_speed_warning_semantics_still_exactly_posted_limit():
    speed = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
    commands = (ROOT / "ios/HUDController/Protocol/HudCommands.swift").read_text()
    assert "HudCommands.speedWarningThreshold(legalLimitMph)" in speed
    assert "SPEED_ALERTS_METHOD=0" in speed
    assert "SPEED_TOLERANCE_VALUE=0" in speed
    assert "legalLimitMph +" not in speed
    assert "command: 2, p1: 9, p2: 9" in commands


def test_night_start_only_marks_writable_headlight_devices_as_joined():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "vehicleJoinedHeadlightIDs.formUnion(ids.filter" in monitor
    assert "pairedDevice($0)?.role?.isHeadlightFed == true" in monitor
    assert "vehicleJoinedHeadlightIDs.formUnion(roleIDs([.dashboard, .centerConsole]).filter { isLogicallyPowered($0) })" not in monitor


def test_fade_loop_does_not_persist_userdefaults_on_every_brightness_frame():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "private func applyRuntimeBrightness(_ id: UUID, percent: Int, reason: String, persist: Bool = false)" in monitor
    assert "if persist { persistPairedDevices() }" in monitor
    assert 'reason: "vehicle shutdown final", persist: true' in monitor
