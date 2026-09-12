from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_post_connect_viewer_is_not_reprimed_after_sta_link_up():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'known-good join sequence: mode 6 once' in app
    assert 'leaving mode 6 untouched' in app
    assert 'no automatic mode-6 retry was sent' in app
    assert 'hud_mjpeg_established=YES' in app
    assert 'Retry HUD display' in (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()

def test_stop_does_not_clear_sta_credentials():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    stop=app.split('func stopHUDU2WSTAHomeProbe()',1)[1].split('// MARK: - Navigation presentation',1)[0]
    assert 'wifiSTAMode(ssid: "", password: "", security: 0)' not in stop
    assert 'preserve STA credentials' in stop

def test_start_is_guarded_while_relay_active():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'if hudU2WLiveRelayActive {' in app
    ui=(ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
    assert '.disabled(state.hudU2WLiveRelayActive ||' in ui

def test_bundled_u2w_v8142_exists_and_is_idempotent():
    b=ROOT/'u2w/v8.14.2_HUD_LiveFrameRelay_DiscoveryKick'
    assert (b/'U2W_Update_v8.14.2_HUD_LiveFrameRelay_DiscoveryKick.img').exists()
    txt=(b/'README.md').read_text().lower()
    assert 'idempotent' in txt
