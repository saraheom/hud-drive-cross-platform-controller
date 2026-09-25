from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
DIAG = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoDiagnosticClient.swift').read_text()
OLD = (ROOT / 'V90_35_3_24_10_RELEASE.md').read_text()

def test_v2410_history_is_preserved_but_current_release_is_passive_diagnostic():
    assert 'U2W v8.29' in OLD
    assert 'v8.27.2-passive-codec-diagnostic-tcp-15332' in VIDEO
    assert 'self.latestFrame = image' in VIDEO
    assert 'self.transportPhase = "LIVE"' in VIDEO

def test_v2411_obd_manual_collection_still_has_no_gps_gate():
    assert 'appVersion=v90.35.3.24.12' in APP
    assert 'no GPS gate; v24.10 length/framing reconstruction retained' in APP
    assert 'guard speedEngine.currentSpeedMph <= 1 else' not in APP

def test_v2411_disables_automatic_mainvideo_predecode_outside_map_mode():
    assert 'app launch — early U2W car-session predecode' not in APP
    assert 'HUD BLE transport ready — reassert continuous predecode' not in APP
    assert 'live U2W Map Mode relay' in APP
    assert 'passive diagnostic commute mode' in APP

def test_v2412_automatic_codec_probe_is_read_only_and_shareable():
    assert 'u2wvideo-diag-start.cgi' in DIAG
    assert 'u2wvideo-diag-bundle.cgi' in DIAG
    assert 'Collect automatic codec diagnostic bundle' in UI
    assert 'do not need to enable Map Mode' in UI
