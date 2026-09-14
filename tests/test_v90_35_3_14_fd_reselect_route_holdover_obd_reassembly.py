from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
ROUTE = (ROOT / 'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()
BLE = (ROOT / 'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()
SETTINGS = (ROOT / 'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
U2W = ROOT / 'u2w/v8.18_MainVideoFDReselect'
SRC = (U2W / 'source/libu2w_mainvideo_live_v818.c').read_text()
INSTALL = (U2W / 'source/install_once.sh').read_text()
UNINSTALL = (U2W / 'source/uninstall_once.sh').read_text()
STATUS = (U2W / 'source/u2wvideo-status-v818.cgi').read_text()


def test_route_holdover_distinguishes_reachable_malformed_from_network_failure():
    assert 'transportFailureHoldoverInterval: TimeInterval = 90.0' in ROUTE
    assert 'malformedResponseHoldoverInterval: TimeInterval = 180.0' in ROUTE
    assert 'HTTP-200 response whose JSON is temporarily malformed' in ROUTE
    assert 'shouldHoldLastActiveRoute(now: now, maximumAge: malformedResponseHoldoverInterval)' in ROUTE
    assert 'shouldHoldLastActiveRoute(now: now, maximumAge: transportFailureHoldoverInterval)' in ROUTE
    assert 'Route feed malformed — holding last guidance' in ROUTE
    # Explicit decoded inactivity remains authoritative and still uses the existing
    # two-sample confirmation logic rather than the transport holdover.
    assert 'confirmations < 2' in ROUTE
    assert 'Ignoring first inactive sample' in ROUTE


def test_obd_has_notification_aware_diagnostic_reassembler():
    for token in [
        'obdDiagnosticWireFrame',
        'obdDiagnosticWireCollecting',
        'consumeDiagnosticBLEFragment',
        'isDiagnosticStartNotification',
        'Interleaved HUD event preserved while diagnostic frame waits',
        'Completed diagnostic frame #',
        'handleDiagnosticPacket(body)',
    ]:
        assert token in BLE
    # Raw bytes must be captured before parser-side dedupe/reassembly.
    assert BLE.index('captureOBDDiagnosticRawBLE(data)') < BLE.index('shouldSuppressDuplicateDiagnosticBLEFragment(data)')
    assert BLE.index('shouldSuppressDuplicateDiagnosticBLEFragment(data)') < BLE.index('consumeDiagnosticBLEFragment(data)')
    # Ordinary STX events must be allowed through without discarding an in-flight diagnostic frame.
    assert 'return false' in BLE[BLE.index('A normal HUD event is interleaved'):BLE.index('A normal HUD event is interleaved') + 900]


def test_v818_exporter_reselects_fd_only_after_h264_bootstrap_and_hooks_close():
    for hook in ['write(int fd', 'send(int fd', 'writev(int fd', 'sendmsg(int fd', 'int close(int fd)']:
        assert hook in SRC
    assert 'validated-sps-pps-idr+close-hook+content-watchdog' in SRC
    assert 'g_candidate_stage>=2 && s.idr' in SRC
    assert 'promote_candidate(fd)' in SRC
    assert 'if(fd==g_main_fd){ invalidate_main(501,1);' in SRC
    assert 'g_main_bad_ps>=2 || g_main_no_h264_bytes>=MAIN_NO_H264_BYTES' in SRC
    assert 'MAIN_NO_H264_BYTES (2u*1024u*1024u)' in SRC


def test_v818_installer_is_gated_and_leaves_v817_streamer_alone():
    assert '2021.03.06.1343' in INSTALL and 'U2W' in INSTALL
    assert '/etc/u2w_mainvideo_v8_11.marker' in INSTALL
    assert '/etc/u2w_v8_17_latest_frame.marker' in INSTALL
    assert '/etc/u2w_v8_18_fd_reselect.marker' in INSTALL
    assert '/etc/boa/cgi-bin/u2wvideo-main-stream.cgi' not in INSTALL
    assert '/etc/boa/cgi-bin/u2wvideo-main-stream.cgi' not in UNINSTALL
    assert 'restored exact v8.11 MainVideo shim/status; v8.17 streamer remains installed' in UNINSTALL
    assert 'fd_reselect=INSTALLED' in STATUS


def test_v818_images_match_recorded_checksums():
    sums = {}
    for line in (U2W / 'U2W_v8.18_SHA256SUMS.txt').read_text().splitlines():
        digest, name = line.split(None, 1)
        sums[name.strip()] = digest
    for name, wanted in sums.items():
        got = hashlib.sha256((U2W / name).read_bytes()).hexdigest()
        assert got == wanted


def test_existing_three_preset_designer_is_preserved():
    assert 'for index in 0..<3' in SETTINGS
    assert 'Self.importedBaselineKey' in SETTINGS
    assert 'Preset 1 *before* loading or applying any preset state' in SETTINGS
    assert 'func selectPreset(_ index: Int)' in SETTINGS
    assert 'func restoreImportedLayout()' in SETTINGS
