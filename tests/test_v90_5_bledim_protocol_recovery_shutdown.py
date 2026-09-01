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
    assert "FFF1 protocol / raw replay" in view
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


def test_engine_off_is_diagnostic_only_and_cannot_cancel_light_animation():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    block = monitor.split("private func confirmEnginePowerOff()", 1)[1].split("private func evaluateVehicleLightingAutomation", 1)[0]
    assert "Engine diagnostic OFF confirmed" in block
    assert "re-arms the one-time engine-start synchronization promotion" in block
    assert "removeFromActiveBreath" not in block
    assert "commitConfirmedHeadlightPower" not in block
    assert "transitionBrightness(" not in block
    assert "performVehicleShutdownFade" not in block


def test_v908_old_courtesy_shutdown_latch_is_removed():
    monitor = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "vehicleShutdownLatched" not in monitor
    assert "vehicleJoinedHeadlightIDs" not in monitor
    assert "headlightJoinTask" not in monitor


def test_v907_bledim_controls_and_breath_are_unlocked():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    device_scope = view.split("if let device = monitor.pairedDevice(deviceID) {", 1)[1]
    assert "bledimUndecoded" not in device_scope
    assert 'section("LIGHT CONTROL")' in device_scope
    assert 'section("ANIMATION")' in device_scope
    assert "Preview Breath" in device_scope
