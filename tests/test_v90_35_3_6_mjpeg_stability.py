from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_app_waits_after_discovery_instead_of_immediate_mode6_bounce():
    s = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'viewer discovery already active; suppressing automatic mode-6 retry' in s
    assert 'try? await Task.sleep(for: .seconds(5))' in s
    assert 'if relay.discoverySeen || relay.clientSeen' in s
    assert 'no discovery observed; viewer retry' in s

def test_relay_status_tracks_client_and_live_frame():
    s = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'clientSeen: text.contains("hud-mjpeg-client-connected")' in s
    assert 'liveFrameSent: text.contains("live-frame-sent")' in s

def test_u2w_robust_mjpeg_server_guards_sigpipe_and_primes_decoder():
    s = (ROOT/'u2w/v8.14.3_HUD_LiveFrameRelay_MJPEGStability/source/u2whud_cast_relay.c').read_text()
    assert 'MSG_NOSIGNAL' in s
    assert 'SO_REUSEADDR' in s
    assert 'fallback-frame-sent' in s
    assert 'live-frame-sent' in s
    assert 'live-jpeg-progressive-fallback' in s
    assert 'mjpeg-send-failed' in s

def test_u2w_status_exposes_stream_diagnostics():
    s = (ROOT/'u2w/v8.14.3_HUD_LiveFrameRelay_MJPEGStability/source/u2whud-status.cgi').read_text()
    assert 'hud_client_seen=YES' in s
    assert 'fallback_frame_sent=YES' in s
    assert 'live_frame_sent=YES' in s
    assert 'mjpeg_send_failed_seen=YES' in s
