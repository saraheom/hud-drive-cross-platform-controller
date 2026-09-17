from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
CANVAS = (ROOT / "ios/HUDController/MapMode/HudMapModeCanvas.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
VEHICLE = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
BLE = (ROOT / "ios/HUDController/Bluetooth/HudBluetoothManager.swift").read_text()


def test_speed_limit_height_and_font_are_persisted_independently():
    for token in ["speedLimitSignHeightScale", "speedLimitFontScale"]:
        assert token in SETTINGS
        assert token in CANVAS
    assert 'HUD.MapMode.speedLimitSignHeightScale' in SETTINGS
    assert 'HUD.MapMode.speedLimitFontScale' in SETTINGS
    assert 'Sign height' in UI
    assert 'Number font size' in UI
    assert 'range: 0.80...2.00' in UI
    assert 'range: 0.70...1.60' in UI
    assert 'width: 42' in CANVAS


def test_obd_trace_is_passive_and_correlates_with_gps_reference():
    assert 'OBD speed protocol trace' in VEHICLE
    assert 'OBD TRACE RX' in BLE
    assert 'updateOBDTraceReferenceSpeed(gpsMph:' in BLE
    assert 'bluetooth?.updateOBDTraceReferenceSpeed(gpsMph: speedMph)' in APP
    assert 'u8@' in BLE
    assert 'u16be@' in BLE
    assert 'u32be@' in BLE
    assert 'f32be@' in BLE
    assert 'the iPhone does not connect to the OBD adapter' in VEHICLE


def test_obd_status_packet_is_explicitly_decoded_for_forensics():
    assert 'body[1] == 7, body[2] == 1' in BLE
    assert 'logger.log("OBD STATUS"' in BLE
    assert 'p1=7,p2=1' in BLE


def test_mode6_to_mode4_sta_persistence_probe_keeps_relay_alive():
    assert 'runHUDMode4STAPersistenceTest' in APP
    assert 'restoreHUDMode6AfterSTAPersistenceTest' in APP
    assert 'STA persistence test → IOS_HUD_MODE(4) only' in APP
    assert 'mode6-only restore (no credentials)' in APP
    assert 'Test mode 6 → 4 STA persistence' in UI
    assert 'Return Map Mode — mode 6 only' in UI
    # Test path must not clear STA credentials or stop U2W.
    block = APP[APP.index('func runHUDMode4STAPersistenceTest'):APP.index('func restoreHUDMode6AfterSTAPersistenceTest')]
    assert 'wifiSTAMode(ssid: "",' not in block
    assert 'u2whud-stop.cgi' not in block


def test_optional_mode6_native_obd_visual_probe_is_retired_from_map_mode():
    # v90.35.3.18 road-test result: item 10 was sent but did not composite above mode 6.
    assert 'Native OBD speed test' not in UI
    assert 'suppressCustomSpeedForNativeOBDProbe: false' in APP
    assert 'startNativeOBDSpeedOverlayProbeIfNeeded()' not in APP.split('private func handleMapModeCastEvent', 1)[1].split('private func startNativeOBDSpeedOverlayProbeIfNeeded', 1)[0]

