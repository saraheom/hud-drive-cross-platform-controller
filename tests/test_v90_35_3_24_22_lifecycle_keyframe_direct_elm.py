from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
ROOTVIEW = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()
ELM = (ROOT / "ios/HUDController/Bluetooth/DirectELM327Manager.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
VEHICLE = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
BT = (ROOT / "ios/HUDController/Bluetooth/HudBluetoothManager.swift").read_text()
V834 = ROOT / "u2w/v8.34_HardBoundedMirrorRawRelay"
V835 = ROOT / "u2w/v8.35_BoundedKeyFrame_v834Mirror"
INSTALL = (V835 / "source/install_once.sh").read_text()
REQUEST_CGI = (V835 / "source/u2wvideo-request-keyframe.cgi").read_text()
HELPER_C = (V835 / "source/u2w_request_keyframe.c").read_text()
HELPER = (V835 / "source/u2w_request_keyframe").read_bytes()


def test_v2422_lifecycle_pauses_decoder_but_preserves_raw_tcp():
    assert 'case .inactive:' in ROOTVIEW
    assert 'applicationWillResignActive()' in ROOTVIEW
    assert 'preserving TCP/HUD cast source while VideoToolbox is lifecycle-paused' in ROOTVIEW
    assert 'worker?.suspendDecoderForLifecycle(reason: reason)' in VIDEO
    assert 'worker?.resumeDecoderAfterLifecycle' in VIDEO
    assert 'stableForegroundDelay: TimeInterval = 0.6' in VIDEO
    assert 'TCP + Annex-B stream PRESERVED' in VIDEO
    assert 'kVTInvalidSessionErr (-12903)' in VIDEO
    assert 'one bounded native keyframe request armed' in VIDEO
    assert 'reconnectAtLiveEdge(reason: "lifecycle' not in VIDEO


def test_v2422_keyframe_request_is_bounded_and_has_no_restart_loop():
    assert 'u2wvideo-request-keyframe.cgi' in VIDEO
    assert 'keyframeRequestCooldown: TimeInterval = 10.0' in VIDEO
    assert 'startupKeyframeDelay: TimeInterval = 1.5' in VIDEO
    assert 'suppressed_cooldown' in VIDEO
    assert 'no retry loop' in VIDEO
    assert 'no process restart/reconnect' in VIDEO


def test_v835_is_incremental_over_exact_v834_mirror_and_v831_raw_relay():
    assert 'v8.34 hard-bounded mirror baseline missing' in INSTALL
    assert 'V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b' in INSTALL
    assert 'V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6' in INSTALL
    assert 'mirror_changed=0' in INSTALL
    assert 'raw_relay_changed=0' in INSTALL
    assert 'cp "$P/libu2w_mainvideo_live.so"' not in INSTALL
    assert 'cp "$P/u2w_mainvideo_relay"' not in INSTALL
    raw_relay = V834 / 'source/u2w_mainvideo_relay'
    assert hashlib.sha256(raw_relay.read_bytes()).hexdigest() == '1c19377dbc9bdc4256dc109053824704a966448ffa9ae8d3472cf76c895e4a90'


def test_v835_helper_contains_exact_zero_payload_requestkeyframe_header():
    header = bytes.fromhex('aa55aa55000000000c000000f3ffffff')
    assert HELPER.count(header) == 1
    assert '/var/run/adb-driver' in HELPER_C
    assert '/var/run/phonemirror' in HELPER_C
    assert 'SYS_sendto' in HELPER_C
    assert '0x0C' in HELPER_C
    assert 'payload length=0' in HELPER_C
    assert 'kill' not in HELPER_C.lower()
    assert 'restart' in HELPER_C.lower()  # only comments explicitly say there is no restart
    assert 'COOLDOWN=8' in REQUEST_CGI
    assert 'rate_limited' in REQUEST_CGI
    assert 'process_restart=NO' in REQUEST_CGI
    assert 'process_signal=NO' in REQUEST_CGI
    assert 'tcp_reconnect=NO' in REQUEST_CGI


def test_direct_elm_probe_tests_coexistence_before_any_ownership_handoff():
    assert 'final class DirectELM327Manager' in ELM
    assert 'scanForPeripherals(withServices: nil' in ELM
    assert 'hudOBDBeforeConnect' in ELM
    assert 'mapModeOwnershipRequested' in ELM
    assert 'Map Mode direct OBD polling START rate=5Hz command=010D only' in ELM
    assert 'selectAndConnect' in ELM
    assert 'guard let bytes = "010D' in ELM
    assert '41 0D' in ELM
    assert '"ATZ\\r"' not in ELM
    assert '"ATSP0\\r"' not in ELM
    assert 'polls only standard 01 0D vehicle speed' in VEHICLE
    assert 'section("MAP MODE OBD")' in VEHICLE
    assert 'state.directELM.ownershipStatus' in VEHICLE
    assert 'Send one 01 0D speed probe' not in VEHICLE
    assert 'let directELM: DirectELM327Manager' in APP
    assert 'hudOBDConnectionConfirmed' in BT


def test_direct_elm_events_flow_into_existing_logs_not_separate_bundle():
    for category in ['ELM SCAN', 'ELM CONN', 'ELM GATT', 'ELM TX', 'ELM RX', 'ELM SPEED']:
        assert category in ELM
    assert 'diagnostics.record("elm327"' in ELM
    assert 'ELM327_DirectProbe.zip' not in ELM
