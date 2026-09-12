from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def test_hud_protocol_resyncs_on_nested_unescaped_stx():
    text=(ROOT/'ios/HUDController/Protocol/HudProtocol.swift').read_text()
    assert 'authoritative new-frame boundary' in text
    assert 'restartedAtNestedSTX' in text
    assert 'buffer.removeSubrange(buffer.startIndex..<index)' in text

def test_fresh_relay_uses_deliberate_sta_clean_reset():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'clean STA reset BEGIN' in app
    assert 'wifiSTAMode(ssid: "", password: "", security: 0)' in app
    assert 'clean STA reset END' in app
    assert 'one-shot STA credential refresh' in app

def test_stale_empty_events_cannot_demote_fresh_connection():
    app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'hudU2WSTAResetInProgress' in app
    assert 'hudU2WIgnoreEmptyStatusUntil' in app
    assert 'stale EMPTY event ignored' in app
