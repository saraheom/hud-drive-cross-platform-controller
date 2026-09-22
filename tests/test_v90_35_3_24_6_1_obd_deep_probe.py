from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BT = (ROOT / 'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
AN = (ROOT / 'ios/HUDController/Vehicle/OBDDeepSpeedAnalyzer.swift').read_text()


def test_v3_probe_is_bounded_and_non_direct():
    assert 'obdDeepSpeedSampleCap = 12_000' in BT
    assert 'no direct OBD connection / no raw PID request' in BT
    assert 'beginOBDDeepSpeedProbe' in BT
    assert 'endOBDDeepSpeedProbe' in BT


def test_v3_analyzer_searches_scaled_lagged_fields_and_pid_410d():
    assert 'lagTenths = [-20, -10, -5, 0, 5, 10, 20]' in AN
    assert 'slopeToMph' in AN
    assert 'rSquared' in AN
    assert 'rmseMph' in AN
    assert 'bytes[i] == 0x41 && bytes[i + 1] == 0x0D' in AN
    assert 'ascii-410D' in AN
    assert 'bcd8' in AN


def test_v3_road_probe_keeps_map_mode_and_hidden_item10():
    assert 'startHUDOBDDeepSpeedProbeV3' in APP
    assert 'for attempt in 1...30' in APP
    assert 'HudOBDItem.drivingVelocity.rawValue' in APP
    assert 'GPS Map Mode speed remains unchanged' in APP
    assert 'Run 90 s OBD deep probe v3' in UI
    assert 'Share OBD speed probe v3 report' in UI
