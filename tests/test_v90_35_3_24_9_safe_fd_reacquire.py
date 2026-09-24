from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
V828 = ROOT / 'u2w/v8.28_SafeFDReacquire'
SELECTOR = (V828 / 'source/libu2w_mainvideo_live_v828.c').read_text()
RELAY = (V828 / 'source/u2w_mainvideo_relay.c').read_text()
INSTALL = (V828 / 'source/install_once.sh').read_text()
STATUS = (V828 / 'source/u2wvideo-relay-status.cgi').read_text()


def test_selector_is_nonblocking_and_never_controls_applecarplay():
    assert 'try_observe_lock' in SELECTOR
    assert 'never block AppleCarPlay media threads' in SELECTOR
    assert 'while(__sync_lock_test_and_set' not in SELECTOR
    assert 'snprintf' not in SELECTOR
    assert 'rename(' not in SELECTOR
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'kill AppleCarPlay' not in INSTALL
    assert 'applecarplay_restart_policy=NEVER' in INSTALL
    assert 'applecarplay_signal_policy=NEVER' in INSTALL


def test_selector_reacquires_only_after_bounded_codec_proof():
    assert 'CANDIDATE_MAX_BYTES' in SELECTOR
    assert 'CANDIDATE_MAX_CALLS' in SELECTOR
    assert 'MAIN_STALE_BYTES (2u*1024u*1024u)' in SELECTOR
    assert 'g_candidate_stage>=2 && s.idr.found' in SELECTOR
    assert 'write_bootstrap' in SELECTOR
    assert 'g_main_fd=fd' in SELECTOR
    assert 'MAIN_OTHER_SCAN_AFTER_CALLS' in SELECTOR
    assert 'RESELECT_CHECK_CALLS 64u' in SELECTOR
    assert '/tmp/u2w_mainvideo_reselect.req' in SELECTOR
    assert 'consume_external_reselect_request' in SELECTOR


def test_v828_relay_fences_every_mirror_generation():
    assert 'U2WH2646' in RELAY
    assert 'relay_version=v8.28-safe-fd-reacquire' in RELAY
    assert 'source-generation-change-reset-codec-wait-next-sps-pps-idr' in RELAY
    assert 'parse_len=0;reset_filter(&live_filter);sps_len=0;pps_len=0' in RELAY
    assert 'client_live=0' in RELAY
    assert 'historical' in RELAY.lower()
    assert 'SO_SNDTIMEO' in RELAY
    assert 'generation_policy=reset-codec-epoch-wait-next-sps-pps-idr' in STATUS
    assert 'RESELECT_AFTER_SOURCE_BYTES (2U*1024U*1024U)' in RELAY
    assert 'full-validator-starved-request-safe-fd-reacquire' in RELAY
    assert 'source_reselect_requests=' in RELAY


def test_ios_quarantines_codec_bad_data_without_tcp_churn():
    assert 'Data("U2WH2646".utf8)' in VIDEO
    assert 'codecBadDataStatus: OSStatus = -8969' in VIDEO
    assert 'hardRecoverAwaitingFreshCodecEpoch' in VIDEO
    assert 'sanitizer.reset(clearParameterSets: true)' in VIDEO
    assert 'TCP PRESERVED; decoder + sanitizer parameter sets cleared' in VIDEO
    assert 'activeSPS = nil' in VIDEO and 'activePPS = nil' in VIDEO
    assert 'preflightRequiredContinuity: TimeInterval = 300.0' in VIDEO
    assert 'LIVE • 5m continuity verified' in VIDEO


def test_obd_zip_manual_collection_has_no_gps_gate():
    assert 'guard speedEngine.currentSpeedMph <= 1 else' not in APP
    assert 'MANUAL COLLECT BEGIN LOG_CATEGORY_OBD' in APP
    assert 'no GPS gate' in APP
    assert 'Collect/reconstruct HUD OBD ZIP (parked)' in UI


def test_release_ui_documents_v249_v828_and_crash_safety():
    assert 'v90.35.3.24.10 pairs with U2W v8.29' in UI
    assert 'never kills/signals/restarts AppleCarPlay' in UI
    assert 'codecBadDataErr (-8969)' in UI
    assert 'LIVE • 5m continuity verified' in UI
