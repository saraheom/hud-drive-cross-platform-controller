#!/usr/bin/env python3
"""Static release checks for v90.35.3.14 + U2W v8.18."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent

def read(rel):
    return (ROOT / rel).read_text(errors='replace')

route = read('ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift')
ble = read('ios/HUDController/Bluetooth/HudBluetoothManager.swift')
settings = read('ios/HUDController/Models/HudMapModeSettings.swift')
src = read('u2w/v8.18_MainVideoFDReselect/source/libu2w_mainvideo_live_v818.c')
install = read('u2w/v8.18_MainVideoFDReselect/source/install_once.sh')
uninstall = read('u2w/v8.18_MainVideoFDReselect/source/uninstall_once.sh')
status = read('u2w/v8.18_MainVideoFDReselect/source/u2wvideo-status-v818.cgi')

checks = {
    'network route holdover 90s': 'transportFailureHoldoverInterval: TimeInterval = 90.0' in route,
    'reachable malformed route holdover 180s': 'malformedResponseHoldoverInterval: TimeInterval = 180.0' in route,
    'decoded inactive still confirmation-gated': 'Ignoring first inactive sample' in route and 'inactiveRouteEndConfirmationInterval: TimeInterval = 5.0' in route,
    'diagnostic BLE frame collector': 'consumeDiagnosticBLEFragment' in ble and 'obdDiagnosticWireFrame' in ble,
    'diagnostic interleaving preserved': 'Interleaved HUD event preserved while diagnostic frame waits' in ble,
    'raw capture precedes parser changes': ble.find('captureOBDDiagnosticRawBLE(data)') < ble.find('shouldSuppressDuplicateDiagnosticBLEFragment(data)') < ble.find('consumeDiagnosticBLEFragment(data)'),
    'three presets preserved': 'for index in 0..<3' in settings and 'Self.importedBaselineKey' in settings,
    'v818 close hook': 'int close(int fd)' in src and 'invalidate_main(501,1)' in src,
    'v818 SPS/PPS/IDR promotion': 'g_candidate_stage>=2 && s.idr' in src and 'promote_candidate(fd)' in src,
    'v818 content watchdog': 'MAIN_NO_H264_BYTES' in src and 'g_main_bad_ps>=2' in src,
    'v818 v817 prerequisite': '/etc/u2w_v8_17_latest_frame.marker' in install,
    'v818 target gate': '2021.03.06.1343' in install and 'U2W' in install,
    'v817 streamer unchanged by installer': 'u2wvideo-main-stream.cgi' not in install and 'u2wvideo-main-stream.cgi' not in uninstall,
    'v818 status fields': 'fd_promotions' in src and 'fd_close_invalidations' in src and 'fd_reselect=INSTALLED' in status,
}
failed=[name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('v90.35.3.14 static failures:\n- ' + '\n- '.join(failed))

sumfile = ROOT/'u2w/v8.18_MainVideoFDReselect/U2W_v8.18_SHA256SUMS.txt'
for line in sumfile.read_text().splitlines():
    digest, name=line.split(None,1)
    got=hashlib.sha256((sumfile.parent/name.strip()).read_bytes()).hexdigest()
    if got != digest:
        raise SystemExit(f'checksum mismatch {name}: {got} != {digest}')

print(f'v90.35.3.14 + U2W v8.18 static checks passed: {len(checks)+2}')
