from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_v90353_live_relay_sources():
    app = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
    relay = (ROOT/'ios/HUDController/MapMode/U2WHUDFrameRelayClient.swift').read_text()
    ui = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
    assert 'U2W v8.14.2' in app
    assert 'sourceMapImage: self.mainVideo.latestFrame' in app
    assert '15331' in relay
    assert 'UInt32(jpeg.count).bigEndian' in relay
    assert 'Live iPhone → U2W → HUD relay' in ui
    assert 'Frames sent' in ui
