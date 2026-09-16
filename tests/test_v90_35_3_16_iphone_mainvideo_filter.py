from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
SAN = (ROOT / 'ios/HUDController/MapMode/H264MainVideoSanitizer.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()


def test_mainvideo_is_map_mode_only():
    transport = APP.split('bluetooth.onTransportReady =', 1)[1].split('bluetooth.onHUDSessionReset =', 1)[0]
    assert 'mainVideo.start' not in transport
    assert 'mainVideo.start(reason: "live U2W Map Mode relay")' in APP
    assert 'mainVideo.stop(reason: "live U2W Map Mode disabled")' in APP
    assert '.disabled(!state.hudU2WLiveRelayActive)' in UI
    assert 'MainVideo connects only while live Map Mode is enabled' in UI


def test_raw_v817_filter_runs_on_iphone():
    assert 'stable U2W v8.11 exporter + v8.17' in VIDEO
    assert 'H264MainVideoSanitizer' in VIDEO
    assert 'expectedWidth: Int = 800' in SAN
    assert 'expectedHeight: Int = 480' in SAN
    assert 'nal.count <= 256' in SAN
    assert 'first & 0x80 == 0' in SAN
    assert 'spsByID' in SAN and 'ppsByID' in SAN
    assert 'parseSlice' in SAN


def test_dirty_bytes_do_not_reconnect_http():
    assert 'decoderStaleFrameInterval: TimeInterval = 20.0' in VIDEO
    assert 'localDecoderResyncCooldown: TimeInterval = 30.0' in VIDEO
    assert 'sourceStaleInterval: TimeInterval = 60.0' in VIDEO
    assert 'sourceReconnectCooldown: TimeInterval = 60.0' in VIDEO
    assert 'requestDecoderResync' in VIDEO
    assert 'raw HTTP stream left open' in VIDEO
    assert 'timeoutIntervalForRequest = 60' in VIDEO
    assert '.now() + 5.0' in VIDEO


def test_obd_probe_end_keeps_connection_path_alive():
    fn = APP.split('func stopHUDU2WNativeOBDSpeedProbe', 1)[1].split('func runHUDMode4STAPersistenceTest', 1)[0]
    assert 'HudOBDItem.none' not in fn
    assert 'keep OBD slot hidden' in fn
    assert 'Post-probe OBD health check found disconnected' in fn


def test_stable_v817_images_are_unchanged():
    expected = {
        'u2w/v8.17_LatestFrame/U2W_Update_v8.17_LatestFrame.img': '6313ac3ec24a8a44456ae18c0a8c7f4a05b39d573479aa72b8bbff844045b19b',
        'u2w/v8.17_LatestFrame/U2W_Update_v8.17_LatestFrame_UNINSTALL.img': '396524a1ce72ec7f39a555b054f5727e31260d6b331ed71e2f68fba2284d4ee3',
    }
    for rel, wanted in expected.items():
        assert hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() == wanted
