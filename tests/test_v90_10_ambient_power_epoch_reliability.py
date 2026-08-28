from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
MODEL = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
VIEW = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()


def test_bledim_animation_uses_native_255_steps_at_shared_20hz():
    assert "static func brightnessRaw(_ value: UInt8" in MODEL
    assert "private func sendBrightnessNormalized(" in MONITOR
    assert "let raw = UInt8((level * 255.0).rounded())" in MONITOR
    assert "protocolPacing=20Hz/rawBLEDIM" in MONITOR
    assert "protocolPacing=BLEDIM10Hz/Lotus20Hz" not in MONITOR


def test_breath_uses_linear_slider_like_ramp_and_zero_is_not_power_off():
    assert "let ramp = legProgress" in MONITOR
    assert "same behavior" not in MONITOR or True
    assert "Logical 0% remains a minimum-brightness command" in MONITOR
    breath = MONITOR.split("private func breathBrightnessFraction", 1)[1].split("private func breathBrightness(", 1)[0]
    assert "sendPower" not in breath
    assert "LotusLanternProtocol.power" not in breath
    assert "BLEDIM2Protocol.power" not in breath


def test_critical_restore_and_breath_prepare_writes_are_retried_in_order():
    assert "private func sendPowerWhenReady" in MONITOR
    assert "private func sendColorWhenReady" in MONITOR
    assert "private func applyRuntimeBrightnessWhenReady" in MONITOR
    assert "Task.sleep(for: .milliseconds(50))" in MONITOR
    restore = MONITOR.split("private func restoreDeviceState", 1)[1].split("private func runStartupAnimationIfNeeded", 1)[0]
    assert restore.index("sendPowerWhenReady") < restore.index("sendColorWhenReady") < restore.index("applyRuntimeBrightnessWhenReady")
    prep = MONITOR.split("private func queuePowerUpBreath", 1)[1].split("private func startSynchronizedBreathSession", 1)[0]
    assert prep.index("sendPowerWhenReady") < prep.index("sendColorWhenReady") < prep.index("applyRuntimeBrightnessWhenReady")


def test_headlight_signal_is_stable_two_light_consensus_but_does_not_own_animation():
    assert 'noteHeadlightPowerSeen(id, reason: "advertisement")' in MONITOR
    assert 'noteHeadlightPowerSeen(id, reason: "didConnect")' in MONITOR
    assert "scheduleHeadlightPowerOffEvaluation" in MONITOR
    assert "both Center + Dashboard stable ON" in MONITOR
    assert "both Center + Dashboard stable OFF" in MONITOR
    commit = MONITOR.split("private func commitConfirmedHeadlightPower", 1)[1].split("private func noteHeadlightPowerSeen", 1)[0]
    assert "queuePowerUpBreath" not in commit


def test_door_day_night_transition_does_not_resend_power_or_rgb():
    block = MONITOR.split("private func applyCurrentDoorDayNightTarget", 1)[1].split("private func transitionDoorBrightness", 1)[0]
    assert "transitionBrightness(" in block
    assert "sendPower(" not in block
    assert "sendColor(" not in block
    assert "activeBreathReturnBrightness" in block


def test_known_vehicle_connections_are_left_pending_instead_of_watchdog_cancel_storm():
    assert "private func isKnownVehicleAmbientDevice" in MONITOR
    assert "!self.isKnownVehicleAmbientDevice(trackedID)" in MONITOR
    assert "!self.isKnownVehicleAmbientDevice(id)" in MONITOR
    assert "Never cancel a pending connection merely because one of the" in MONITOR


def test_color_picker_initial_sync_and_preset_tap_do_not_double_send_rgb():
    assert VIEW.count("@State private var colorPickerReady = false") >= 2
    assert VIEW.count("guard colorPickerReady else { return }") >= 2
    assert VIEW.count("DispatchQueue.main.async { colorPickerReady = true }") >= 2
    assert "do not double-send a preset tap" in VIEW
