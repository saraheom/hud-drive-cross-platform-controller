from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BT = (ROOT/'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/VehicleView.swift').read_text()
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()


def test_raw_capture_is_bounded_and_preparser():
    assert 'obdDiagnosticRawCaptureLimitBytes = 8 * 1024 * 1024' in BT
    assert 'captureOBDDiagnosticRawBLE(data)' in BT
    assert BT.index('captureOBDDiagnosticRawBLE(data)') < BT.index('self.rxBuffer.append(data)')
    assert 'HUD_OBD_RawBLE_' in BT


def test_category_and_chunk_forensics_are_logged():
    assert 'CATEGORY MISMATCH' in BT
    assert 'declared=' in BT and 'available=' in BT
    assert 'obdDiagnosticObservedCategories' in BT
    assert 'Malformed diagnostic chunk category=' in BT


def test_speed_pid_and_elm_signatures_are_scanned():
    for token in ['41 0D@', '01 0D@', '010D', '410D', 'ELM327', 'ATZ']:
        assert token in BT
    assert 'speed:' in BT


def test_native_speed_probe_forces_unthrottled_rx_forensics():
    assert 'beginOBDSpeedProbeForensics(duration: 13.5' in APP
    assert 'OBD PROBE RX' in BT
    assert 'automatic Map Mode OBD overlay' in APP


def test_vehicle_ui_exposes_raw_capture_without_adapter_change():
    assert 'Stop & save raw' in UI
    assert 'Share raw HUD BLE capture' in UI
    assert 'Returned categories' in UI


def test_mainvideo_reliability_baseline_is_unchanged():
    assert 'latestFrame' in VIDEO
    assert 'decoderStaleFrameInterval' in VIDEO
