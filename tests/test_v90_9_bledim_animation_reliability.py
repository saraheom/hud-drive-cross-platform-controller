from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
VIEW = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()


def test_bledim_animation_uses_native_raw_resolution_and_per_device_sequence():
    assert "private func sendBrightnessNormalized(" in MONITOR
    assert "let raw = UInt8((level * 255.0).rounded())" in MONITOR
    assert "protocolPacing=20Hz/rawBLEDIM" in MONITOR
    assert "private var bledimSequenceByID: [UUID: UInt8]" in MONITOR
    assert "nextBLEDIMSequence(for id: UUID)" in MONITOR
    assert "bledimSequenceByID[id] = 0x08" in MONITOR
    assert "private var bledimSequence: UInt8" not in MONITOR


def test_animation_uses_wall_clock_and_backpressure_instead_of_blind_frame_queueing():
    assert "let startedAt = Date()" in MONITOR
    assert "elapsed / totalDuration" in MONITOR
    assert "peripheral.canSendWriteWithoutResponse" in MONITOR
    assert "retries the newest frame later" in MONITOR
    assert "applyRuntimeBrightnessWhenReady" in MONITOR
    assert "Timed out waiting to send final brightness" in MONITOR


def test_watchdog_does_not_rediscover_gatt_after_control_is_ready():
    assert "discoverServicesIfNeeded" in MONITOR
    assert "if !force, writeCharacteristicsByID[id] != nil" in MONITOR
    assert "serviceDiscoveryRetrySeconds" in MONITOR
    assert 'discoverServicesIfNeeded(peripheral, reason: "connected maintenance")' in MONITOR


def test_repeated_breath_preview_cannot_replace_initial_brightness_with_mid_animation_value():
    assert "if activeBreathIDs.contains(id)" in MONITOR
    assert "initial/return brightness preserved" in MONITOR
    assert "initialBrightness = device.runtimeBrightness" in MONITOR
    assert "activeBreathStartBrightness[id] = initialBrightness" in MONITOR
    assert "runtimeTarget = device.brightness" in MONITOR


def test_repetitive_bledim_notifications_and_animation_packet_logs_are_reduced():
    assert "lastBLEDIMNotifyLogAtByID" in MONITOR
    assert "repetitive BLEDIM2 notification, rate-limited" in MONITOR
    assert "let logPacket = signature == 0 || signature == maxSignature" in MONITOR


def test_five_presets_have_visible_edit_controls_for_device_and_group_rows():
    assert "pencil.circle.fill" in VIEW
    assert "tap its pencil to save the current picker color" in VIEW
    assert "Replace preset" in VIEW
    assert "setDevicePresetColor" in MONITOR
    assert "setGroupPresetColor" in MONITOR
