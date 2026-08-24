from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_v907_bledim_uses_recovered_official_ios_protocol_and_keeps_raw_lab():
    model = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert "Control protocol recovered from official BLEDIM2 iOS Bluetooth capture" in model
    assert "55 AA <sequence> <command> <length-be16>" in model
    assert "command: 0x80" in model
    assert "command: 0x82" in model
    assert "command: 0x88" in model
    assert "sendRawBLEDIMHex" in monitor
    assert "BLEDIM2 FFF1 control ready" in monitor
    assert "Normal BLEDIM controls disabled" not in view
    assert "bledimUndecoded" not in view
    assert "F000FFC0/FFC1/FFC2" in view
    assert "0x7E, 0xFF, 0x04" not in model


def test_v905_reads_bledim_device_information_and_advertisement_metadata():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "captureBLEDIMAdvertisement" in monitor
    assert "CBAdvertisementDataManufacturerDataKey" in monitor
    assert "CBAdvertisementDataServiceDataKey" in monitor
    assert "recordBLEDIMDiagnosticValue" in monitor
    for uuid in ["2A29", "2A24", "2A25", "2A27", "2A26", "2A28", "2A23", "2A2A", "2A50", "2A19"]:
        assert uuid in monitor
    assert 'serviceValue == "180A" || serviceValue == "180F"' in monitor


def test_v905_engine_off_does_not_try_to_fade_door_and_keeps_courtesy_latch():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("private func performVehicleShutdownFade", 1)[1].split("/// Convenient stationary test", 1)[0]
    assert "Door power is expected to disappear immediately" in block
    assert "role.isHeadlightFed" in block
    assert "device.role != nil" not in block
    assert "vehicleShutdownLatched = true" in block
    assert "Shutdown latch remains until next engine ON" in block
    assert 'pairedDevices[index].lastAppliedBrightness = 0' in block


def test_v905_engine_off_arms_latch_even_if_no_light_is_ready_yet():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("private func confirmEnginePowerOff()", 1)[1].split("private func evaluateVehicleLightingAutomation", 1)[0]
    assert "vehicleSessionActive" not in block
    assert 'performVehicleShutdownFade(trigger: "engine power OFF")' in block
    assert "post-lock" in monitor


def test_v907_bledim_controls_and_animation_are_unlocked():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    device_scope = view.split("if let device = monitor.pairedDevice(deviceID) {", 1)[1]
    assert "bledimUndecoded" not in device_scope
    assert "Recovered official BLEDIM2 protocol" in device_scope
    assert "power 0x80" in view
    assert "RGB 0x82" in view
    assert "brightness 0x88" in view
    assert 'section("STARTUP ANIMATION")' in device_scope
