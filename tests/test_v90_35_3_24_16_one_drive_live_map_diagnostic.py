from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
CLIENT = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
REC = (ROOT / 'ios/HUDController/MapMode/LiveMapDiagnosticRecorder.swift').read_text()
RELAY = (ROOT / 'ios/HUDController/MapMode/U2WHUDFrameRelayClient.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()


def test_v2416_version_and_unchanged_v831_pair():
    assert 'appVersion=v90.35.3.24.29' in APP
    assert 'v90.35.3.24.29 MainVideo client for U2W v8.38 read-only startup bootstrap + v8.37 forensic seam capture + unchanged v8.35 helper + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay' in CLIENT
    assert 'v8.34-hard-bounded-mirror-v831-raw-tcp-15332' in CLIENT


def test_exact_raw_tcp_bytes_are_captured_before_annexb_parser():
    raw_block = CLIENT.index('private func receiveRawBytes')
    section = CLIENT[raw_block: raw_block + 1800]
    assert 'self.onRawBytes?(data)' in section
    assert ('self.annexBParser.append(data)' in section or 'self.feedStartupBytes(data' in section)
    assert 'for nal in annexBParser.append(data)' in CLIENT
    parser_call = 'self.annexBParser.append(data)' if 'self.annexBParser.append(data)' in section else 'self.feedStartupBytes(data'
    assert section.index('self.onRawBytes?(data)') < section.index(parser_call)
    assert 'diagnosticRecorder.ingestRawH264(data)' in CLIENT


def test_bounded_startup_pre_post_tail_capture_contract():
    assert 'startupLimit = 8 * 1024 * 1024' in REC
    assert 'prebufferLimit = 4 * 1024 * 1024' in REC
    assert 'postbufferLimit = 4 * 1024 * 1024' in REC
    assert 'maximumEvidenceWindows = 6' in REC
    assert 'raw_tail_last_4MiB.h264' in REC
    assert 'evidence_drop' in REC


def test_fault_and_recovery_boundaries_trigger_evidence_windows():
    for marker in [
        'decoder_output_stall',
        'raw_source_stall',
        'decoder_recovery',
        'decoder_error',
        'tcp_terminal',
        'frame_recovered',
        'first_decoded_frame',
    ]:
        assert marker in CLIENT


def test_one_tap_bundle_includes_cross_layer_evidence():
    assert 'Collect Live Map Diagnostic ZIP (parked)' in UI
    assert 'HUD_app_session.log' in REC
    assert 'iphone_state.txt' in REC
    assert 'timeline.jsonl' in REC
    assert 'U2W_MainVideo_Passive_Diagnostic.tar.gz' in APP
    for endpoint in [
        'u2wvideo-relay-status.cgi',
        'u2wvideo-status.cgi',
        'u2whud-status.cgi',
        'u2wrgd-live.cgi',
        'u2wvideo-diag-status.cgi',
        'u2wvideo-diag-bundle.cgi',
    ]:
        assert endpoint in APP


def test_hud_output_sample_is_retained_for_bundle():
    assert 'lastSuccessfulJPEG' in RELAY
    assert 'self.lastSuccessfulJPEG = jpeg' in RELAY
    assert 'hud_last_confirmed_jpeg' in APP


def test_passive_source_probe_is_auto_ensured_without_mainvideo_autostart():
    assert 'mainVideoDiagnostic?.ensureStarted(reason: "v24.18 one-drive live-map diagnostic")' in APP
    reachable = APP.index('routeGuidance.onAdapterReachable')
    block = APP[reachable: reachable + 1500]
    assert '.start(reason:' not in block or 'mainVideo.start(reason:' not in block
    assert 'MainVideo intentionally idle unless Map Mode is explicitly enabled' in block
