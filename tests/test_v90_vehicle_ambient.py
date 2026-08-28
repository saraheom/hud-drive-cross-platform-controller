from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_bledim2_fff1_transport_uses_official_ios_capture_protocol():
    model = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "static let fff1" in model
    assert "static let writeCharacteristicUUID = CBUUIDString.fff1" in model
    assert "0x55, 0xAA, sequence, command" in model
    assert "command: 0x80" in model
    assert "command: 0x82" in model
    assert "command: 0x88" in model
    assert "BLEDIM2 FFF0/FFF1 control ready" in monitor


def test_vehicle_roles_match_physical_test_devices():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert 'hasPrefix("FBD8C9A0-")' in monitor
    assert 'return .door' in monitor
    assert 'hasPrefix("7A3B5F81-")' in monitor
    assert 'return .dashboard' in monitor
    assert 'hasPrefix("51FA23D6-")' in monitor
    assert 'return .centerConsole' in monitor


def test_smooth_brightness_transition_is_shared_and_does_not_rewrite_preference_per_frame():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "private func transitionBrightness(" in monitor
    assert "let timelineTick = 0.05" in monitor
    assert "private func sendBrightnessNormalized(" in monitor
    assert "protocolPacing=20Hz/rawBLEDIM" in monitor
    assert "let starts = Dictionary" in monitor
    assert "guard lastSentLevel[id] != signature else { continue }" in monitor
    assert "if persist { persistPairedDevices() }" in monitor
    assert "group manual brightness" in monitor


def test_vehicle_automation_only_classifies_day_night_for_door():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "beginVehicleStartupClassification" in monitor
    assert "finishVehicleStartupClassification" in monitor
    assert "Simplified startup classification complete" in monitor
    assert "applyCurrentDoorDayNightTarget" in monitor
    assert "fadeInNewHeadlightDevices" not in monitor
    assert "performVehicleShutdownFade" not in monitor


def test_engine_power_uses_hud_and_obd_but_engine_off_does_not_drive_lights():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    appstate = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
    obd = (ROOT / "ios/HUDController/Vehicle/HudOBDController.swift").read_text()
    assert "func hudTransportPowerSignal(_ present: Bool)" in monitor
    assert "func obdPowerSignal(_ present: Bool)" in monitor
    assert "scheduleEnginePowerOffConfirmation" in monitor
    assert "directOBDWitnessProven" in monitor
    assert "Engine power OFF confirmed; v90.8 leaves all ambient lights" in monitor
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
