from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def test_hud_protocol_resyncs_on_nested_unescaped_stx():
    text=(ROOT/'ios/HUDController/Protocol/HudProtocol.swift').read_text()
    assert 'authoritative new-frame boundary' in text
    assert 'restartedAtNestedSTX' in text
    assert 'buffer.removeSubrange(buffer.startIndex..<index)' in text

def test_fresh_relay_does_not_erase_saved_sta_network():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'known-good join sequence: mode 6 once' in app
    assert 'wifiSTAMode(ssid: "", password: "", security: 0)' not in app
    assert 'one-shot Wi-Fi credential refresh' in app
    assert 'IOS_KIVICCAST_STA_MODE(6) [single start]' in app

def test_status6_with_valid_ip_is_soft_connected():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'status=6' in app
    assert 'isUsableHUDSTAAddress' in app
    assert 'Wi-Fi IP acquired — starting HUD display…' in app
    assert 'STA has DHCP address despite status=6' in app
