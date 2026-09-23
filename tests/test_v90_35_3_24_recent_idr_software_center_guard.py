from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
AMBIENT = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
RELAY = (ROOT / 'u2w/v8.24_RecentIDRRelay/source/u2w_mainvideo_relay.c').read_text()
STATUS = (ROOT / 'u2w/v8.24_RecentIDRRelay/source/u2wvideo-relay-status.cgi').read_text()


def test_v824_recent_idr_closes_client_after_keyframe_race_without_big_gop_burst():
    assert 'U2WH2643' in RELAY
    assert 'U2WH2642' in VIDEO and 'U2WH2643' in VIDEO and 'acceptedMagics' in VIDEO
    assert '#define RECENT_CAP (4*1024*1024)' in RELAY
    assert 'recent-anchor-cap-exceeded-wait-next-idr' in RELAY
    assert 'client-connected-recent-anchor-available' in RELAY
    assert 'client-live-bootstrap-recent-idr-anchor' in RELAY
    assert 'begin_live_from_recent_anchor' in RELAY
    assert 'cat /tmp/u2w_h264_relay_status.txt' in STATUS
    assert 'recent_anchor_ready=' in RELAY
    assert 'recent_anchor_overflows=' in RELAY
    assert 'recent_bootstraps=' in RELAY
    assert '17-20 MiB' in RELAY


def test_ios_uses_v824_and_bounded_exact_framing_with_software_decoder_preference():
    assert 'v8.24/v8.25/v8.26/v8.27-tcp-15332' in VIDEO
    assert 'validated/recent/live IDR bootstrap enabled' in VIDEO
    assert 'receiveExactly' in VIDEO
    assert 'maximumNALBytes = 512 * 1024' in VIDEO
    assert 'kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder' in VIDEO
    assert 'NSNumber(value: false)' in VIDEO
    assert 'software-preferred=1' in VIDEO


def test_decoder_recovery_reconnects_to_recent_anchor_instead_of_dead_session_loop():
    assert 'kVTInvalidSessionErr (-12903)' in VIDEO
    assert 'bounded recovery attempt #1' in VIDEO
    assert 'WAITING_FRESH_IDR' in VIDEO
    assert 'stale-output watchdog' in VIDEO and 'performBoundedDecoderRecovery' in VIDEO
    assert 'bounded decoder recovery persistent-GOP reseed' in VIDEO
    assert 'Decoder recovery • waiting for a clean IDR' in VIDEO


def test_mainvideo_warms_before_hud_ble_and_survives_hud_ble_transport_loss():
    assert 'app launch — early U2W car-session predecode' in APP
    disconnect = APP.split('bluetooth.onTransportDisconnected =', 1)[1]
    preserve_index = disconnect.index('HUD BLE disconnected — preserve U2W car-session predecode')
    callback_prefix = disconnect[:preserve_index + 128]
    assert 'HUD BLE disconnected — preserve U2W car-session predecode' in callback_prefix
    assert 'mainVideo.stop' not in callback_prefix


def test_center_only_day_guard_is_one_second_and_dashboard_does_not_gate_day():
    assert 'centerDayGuardSeconds: TimeInterval = 1.0' in AMBIENT
    assert 'Center-only DAY guard armed' in AMBIENT
    assert 'Dashboard not required' in AMBIENT
    assert 'Center evidence returned during DAY guard' in AMBIENT
    assert 'Dashboard+Center BOTH-OFF stable; fast corroborated DAY commit' not in AMBIENT
