from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
ROUTE = (ROOT/'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
U2W = ROOT/'u2w/v8.19_SafeMainVideoFilter'
SRC = (U2W/'source/u2w_mainvideo_streamer.c').read_text()
INSTALL = (U2W/'source/install_once.sh').read_text()
UNINSTALL = (U2W/'source/uninstall_once.sh').read_text()

def test_mainvideo_recovery_is_conservative():
    assert 'decoderStaleFrameInterval: TimeInterval = 15.0' in VIDEO
    assert 'sourceStaleInterval: TimeInterval = 30.0' in VIDEO
    assert 'freshnessReconnectCooldown: TimeInterval = 30.0' in VIDEO
    assert 'conservative v8.19 reseed' in VIDEO
    assert 'nal.count <= 256' in VIDEO

def test_route_inactive_requires_five_seconds():
    assert 'inactiveRouteEndConfirmationInterval: TimeInterval = 5.0' in ROUTE
    assert 'inactiveStartedAtBySource' in ROUTE
    assert 'holding active HUD guidance for 5s' in ROUTE
    assert 'transportFailureHoldoverInterval: TimeInterval = 90.0' in ROUTE
    assert 'malformedResponseHoldoverInterval: TimeInterval = 180.0' in ROUTE

def test_obd_probe_can_wait_for_connection():
    assert 'hudU2WNativeOBDProbePending' in APP
    assert 'waiting up to 20s' in APP
    assert 'Date().addingTimeInterval(20.0)' in APP
    assert 'obd.connect(force: true)' in APP
    assert '!state.obd.connected' not in UI.split('Start 12s native OBD speed probe',1)[1].split('if state.hudU2WNativeOBDProbeActive',1)[0]

def test_u2w_v819_is_cgi_only_and_does_not_patch_applecarplay():
    assert 'cp "$P/u2w_mainvideo_streamer" "$DST"' in INSTALL
    assert 'libu2w_mainvideo' not in INSTALL
    assert 'LD_PRELOAD' not in INSTALL
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'mainvideo_exporter=v8.11-unchanged' in INSTALL
    assert 'applecarplay_hook_changes=none' in INSTALL
    assert 'restored exact v8.17 LatestFrame CGI streamer' in UNINSTALL

def test_u2w_v819_filter_is_strict_and_bounded():
    assert '#define EXPECT_WIDTH 800' in SRC
    assert '#define EXPECT_HEIGHT 480' in SRC
    assert '#define MAX_PARAM_BYTES 256' in SRC
    assert 'parse_sps' in SRC and 'parse_pps' in SRC and 'parse_slice' in SRC
    assert 'X-U2W-Streamer: v8.19-safe-mainvideo-filter' in SRC
    assert 'X-U2W-AppleCarPlay-Hooks: none' in SRC
    assert 'nap_ms(1000)' in SRC

def test_u2w_images_match_sha_file():
    sums = {}
    for line in (U2W/'U2W_v8.19_SHA256SUMS.txt').read_text().splitlines():
        digest, name = line.split(None, 1)
        sums[name.strip()] = digest
    for name, digest in sums.items():
        assert hashlib.sha256((U2W/name).read_bytes()).hexdigest() == digest
