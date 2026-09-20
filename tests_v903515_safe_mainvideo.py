from pathlib import Path
ROOT=Path(__file__).resolve().parent
video=(ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
route=(ROOT/'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()
app=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
u2w=ROOT/'u2w/v8.19_SafeMainVideoFilter'
checks={
 'v819 source': (u2w/'source/u2w_mainvideo_streamer.c').exists(),
 'no AppleCarPlay payload': not any('AppleCarPlay' in p.name for p in (u2w/'source').iterdir()),
 'bounded local decoder recovery': 'decoderStaleFrameInterval: TimeInterval = 3.0' in video and 'HARD decoder recovery, reconnect recent-IDR bootstrap' in video,
 'bounded source-silence hold': 'sourceStaleInterval: TimeInterval = 15.0' in video,
 '5s route inactive hold': 'inactiveRouteEndConfirmationInterval: TimeInterval = 5.0' in route,
 'OBD pending state': 'hudU2WNativeOBDProbePending' in app,
 'OBD connect wait': 'Date().addingTimeInterval(20.0)' in app,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('v90.35.3.15 static failures:\n- '+'\n- '.join(failed))
print(f'v90.35.3.15 static checks passed: {len(checks)}')
