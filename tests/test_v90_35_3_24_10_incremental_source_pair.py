from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()

def test_v2410_pairs_to_v829_without_changing_wire_or_decoder_strategy():
    assert 'v8.29-incremental-source-acquire+v8.28-relay-core' in VIDEO
    assert 'Data("U2WH2646".utf8)' in VIDEO
    assert 'codecBadDataErr (-8969) quarantined current H.264 epoch' in VIDEO
    assert 'self.latestFrame = image' in VIDEO
    assert 'self.transportPhase = "LIVE"' in VIDEO

def test_v2410_obd_manual_collection_still_has_no_gps_gate():
    assert 'appVersion=v90.35.3.24.10' in APP
    assert 'no GPS gate; v24.10 length/framing reconstruction active' in APP
    assert 'guard speedEngine.currentSpeedMph <= 1 else' not in APP

def test_v2410_ui_explains_immediate_map_and_extended_stability_only():
    assert 'v90.35.3.24.10 pairs with U2W v8.29' in UI
    assert 'live map image should appear as soon as the first valid frame decodes' in UI
    assert 'only the extended stability milestone' in UI
