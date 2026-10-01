from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
ROOTVIEW = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()

def test_navigation_mode_has_zero_automatic_mainvideo_starts():
    starts = [line.strip() for line in APP.splitlines() if "mainVideo.start(" in line]
    assert starts == [
        'mainVideo.start(reason: "app-only live preview")',
        'self.mainVideo.start(reason: "physical Map Mode live source (optional)")',
    ]
    assert "Route Guidance endpoint reachable; MainVideo intentionally idle" in APP
    assert 'mainVideo.start(reason: "HUD BLE' not in APP
    assert 'mainVideo.start(reason: "Route Guidance' not in APP

def test_map_mode_proves_first_jpeg_before_mode6_but_does_not_require_mainvideo():
    prewarm = APP.index("Preparing first HUD Map Mode frame")
    first_jpeg_guard = APP.index("guard firstFrameDelivered else", prewarm)
    mode6 = APP.index("HudCommands.kivicMode(6)", first_jpeg_guard)
    assert prewarm < first_jpeg_guard < mode6
    assert 'physical Map Mode no longer depends on MainVideo readiness' in APP
    assert 'physical Map Mode live source (optional)' in APP
    assert 'Live map unavailable — Navigation retained' not in APP

def test_map_mode_stop_stops_experimental_video_work():
    assert 'mainVideo.stop(reason: "live U2W Map Mode disabled — restore Navigation-only adapter load")' in APP
    assert "u2wvideo-relay-stop.cgi" in VIDEO

def test_raw_v831_moves_h264_semantics_to_iphone():
    assert 'Data("U2WH2648".utf8)' in VIDEO
    assert "receiveRawBytes" in VIDEO
    assert "annexBParser.append(data)" in VIDEO
    assert "adapter parser/cache=NONE" in VIDEO

def test_v831_transport_fails_closed_without_reconnect_loop():
    assert "FAIL CLOSED, no reconnect loop" in VIDEO
    assert 'self.transportPhase = "FAILED_SAFE"' in VIDEO

def test_decoder_recovery_requires_real_output_callback():
    assert "successful compressed-AU submission is NOT proof of decoder recovery" in VIDEO
    assert "Decoder recovery CONFIRMED by successful image callback" in VIDEO

def test_post_ready_sta_status_never_bounces_mode_automatically():
    assert "post-ready STA diagnostic only" in APP
    assert "no automatic mode change" in APP

def test_background_preserves_live_session_instead_of_guaranteed_teardown():
    background = ROOTVIEW.split("case .background:", 1)[1].split("default:", 1)[0]
    assert "preserving decoder/TCP/HUD cast session" in background
    assert "state.stopHUDU2WSTAHomeProbe()" not in background
    assert 'state.stopMainVideoPreview(reason: "app background")' not in background
    assert "state.mainVideo.applicationDidEnterBackground()" in background
