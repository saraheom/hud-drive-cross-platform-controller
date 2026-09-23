from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
SAN = (ROOT / 'ios/HUDController/MapMode/H264MainVideoSanitizer.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()


def test_mainvideo_uses_continuous_dedicated_tcp():
    transport = APP.split('bluetooth.onTransportReady =', 1)[1].split('bluetooth.onHUDSessionReset =', 1)[0]
    assert 'mainVideo.start(reason: "HUD BLE transport ready — reassert continuous predecode")' in transport
    assert 'mainVideo.start(reason: "live U2W Map Mode relay")' in APP
    assert 'keep continuous predecode alive' in APP
    assert 'U2W H.264 relay' in UI


def test_dedicated_tcp_filter_runs_on_iphone():
    assert 'v8.24/v8.25/v8.26/v8.27-tcp-15332' in VIDEO
    assert 'U2WMainVideoTCPWorker' in VIDEO
    assert 'U2WH2642' in VIDEO and 'U2WH2643' in VIDEO
    assert 'port: 15332' in VIDEO
    assert 'H264MainVideoSanitizer' in VIDEO
    assert 'expectedWidth: Int = 800' in SAN
    assert 'expectedHeight: Int = 480' in SAN
    assert 'nal.count <= 256' in SAN
    assert 'first & 0x80 == 0' in SAN
    assert 'spsByID' in SAN and 'ppsByID' in SAN
    assert 'parseSlice' in SAN


def test_video_self_healing_does_not_use_long_lived_boa():
    assert 'decoderStaleFrameInterval: TimeInterval = 3.0' in VIDEO
    assert 'WAITING_LIVE_IDR' in VIDEO
    assert 'validated/recent/live IDR bootstrap enabled' in VIDEO
    assert 'sourceStaleInterval: TimeInterval = 15.0' in VIDEO
    assert 'sourceReconnectCooldown: TimeInterval = 15.0' in VIDEO
    assert 'kVTInvalidSessionErr (-12903)' in VIDEO
    assert 'u2wvideo-relay-start.cgi' in VIDEO
    assert 'u2wvideo-relay-status.cgi' in VIDEO
    assert 'u2wvideo-main-stream.cgi' not in VIDEO


def test_obd_probe_end_keeps_connection_path_alive():
    fn = APP.split('func stopHUDU2WNativeOBDSpeedProbe', 1)[1].split('func runHUDMode4STAPersistenceTest', 1)[0]
    assert 'HudOBDItem.none' not in fn
    assert 'fullScreen(false)' not in fn
    assert 'GPS JPEG speed/full-screen state unchanged' in fn
    assert 'obd.disconnect' not in fn


def test_stable_v817_images_are_unchanged():
    expected = {
        'u2w/v8.17_LatestFrame/U2W_Update_v8.17_LatestFrame.img': '6313ac3ec24a8a44456ae18c0a8c7f4a05b39d573479aa72b8bbff844045b19b',
        'u2w/v8.17_LatestFrame/U2W_Update_v8.17_LatestFrame_UNINSTALL.img': '396524a1ce72ec7f39a555b054f5727e31260d6b331ed71e2f68fba2284d4ee3',
    }
    for rel, wanted in expected.items():
        assert hashlib.sha256((ROOT / rel).read_bytes()).hexdigest() == wanted
