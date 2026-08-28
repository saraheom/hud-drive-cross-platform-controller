from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_bledim_animation_matches_official_100ms_slider_cadence():
    assert "pairedDevice(id)?.protocolKind == .bledim2 ? 0.10 : 0.05" in MONITOR
    assert "if !isBLEDIM2, lastSentLevel[id] == signature { continue }" in MONITOR
    assert "official iOS slider sends at ~100 ms cadence" in MONITOR


def test_bledim_reconnect_uses_minimal_control_gatt_path():
    assert "Targeted BLEDIM2 FFF0 service discovery requested" in MONITOR
    assert "discoverServices([CBUUID(string: BLEDIM2Protocol.serviceUUID)])" in MONITOR
    assert "[CBUUID(string: BLEDIM2Protocol.writeCharacteristicUUID)]" in MONITOR
    assert 'serviceValue == "180A" || serviceValue == "180F"' not in MONITOR
    assert "peripheral.readValue(for: characteristic)" not in MONITOR


def test_bledim_write_ready_callback_can_resume_pending_steady_state_recovery():
    assert "peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)" in MONITOR
    assert 'reason: "CoreBluetooth write-without-response ready"' in MONITOR
