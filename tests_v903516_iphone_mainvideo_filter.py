#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parent
video = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
san = (ROOT/'ios/HUDController/MapMode/H264MainVideoSanitizer.swift').read_text()
app = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
ui = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
checks = {
    'iPhone-side H264 sanitizer': 'H264MainVideoSanitizer' in video and 'parseSPS' in san and 'parsePPS' in san and 'parseSlice' in san,
    '800x480 validation': 'expectedWidth: Int = 800' in san and 'expectedHeight: Int = 480' in san,
    'Map Mode only start': 'mainVideo.start(reason: "live U2W Map Mode relay")' in app,
    'Map Mode stop closes video': 'mainVideo.stop(reason: "live U2W Map Mode disabled")' in app,
    'no transport-ready video start': 'mainVideo.start' not in app.split('bluetooth.onTransportReady =',1)[1].split('bluetooth.onHUDSessionReset =',1)[0],
    'fresh bytes keep decoder session alive': 'KEEP decoder session and continue validated P-frames' in video,
    'source silence is 60s': 'sourceStaleInterval: TimeInterval = 60.0' in video,
    'UI exposes filter counters': 'iPhone H.264 filter' in ui and 'sanitizerSummary' in ui,
    'manual video reconnect gated by Map Mode': '.disabled(!state.hudU2WLiveRelayActive)' in ui,
    'probe end does not clear stock slot': 'HudOBDItem.none' not in app.split('func stopHUDU2WNativeOBDSpeedProbe',1)[1].split('func runHUDMode4STAPersistenceTest',1)[0],
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('v90.35.3.16 static failures:\n- '+'\n- '.join(failed))
print(f'v90.35.3.16 iPhone MainVideo static checks passed: {len(checks)}')
