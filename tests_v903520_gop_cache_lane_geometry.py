#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parent
read=lambda r:(ROOT/r).read_text(encoding='utf-8')
video=read('ios/HUDController/MapMode/U2WMainVideoClient.swift')
canvas=read('ios/HUDController/MapMode/HudMapModeCanvas.swift')
app=read('ios/HUDController/App/AppState.swift')
ui=read('ios/HUDController/UI/NavigationHUDPreviewCard.swift')
relay=read('u2w/v8.22_DedicatedH264Relay/source/u2w_mainvideo_relay.c')
cast=read('u2w/v8.22_DedicatedH264Relay/source/u2whud_cast_relay_v822.c')
install=read('u2w/v8.22_DedicatedH264Relay/source/install_once.sh')
checks={
 'dedicated relay tails v8.11 live path':'/tmp/u2w_mainvideo_live.h264' in relay,
 'dedicated relay uses separate TCP port':'15332' in relay and 'U2WH2641' in video,
 'gop cache is in-process not shared file':'gop_buf' in relay and '/tmp/u2w_mainvideo_gop_cache.h264' not in relay,
 'startup scan reaches live edge before bootstrap':'startup_scan_complete' in relay and 'startup-scan-complete-live-tail' in relay,
 'active client has bounded send timeout':'SO_SNDTIMEO' in relay and 'tv.tv_sec=2' in relay,
 'installer clears legacy long-lived streamers':'killall u2w_mainvideo_streamer' in install,
 'installer leaves AppleCarPlay untouched':'pkill AppleCarPlay' not in install and 'killall AppleCarPlay' not in install and 'LD_PRELOAD' not in install,
 'final HUD MJPEG sender has timeout watchdog':'SO_SNDTIMEO' in cast and 'SO_RCVTIMEO' in cast and 'mjpeg-send-failed' in cast,
 'app starts continuous predecode on HUD BLE':'HUD BLE transport ready — continuous predecode' in app,
 'app exposes relay status':'adapterCacheSummary' in video and 'U2W H.264 relay' in ui,
 'app logs composite heartbeat':'MAP RENDER HEARTBEAT' in app,
 'no fake route preview':'allowDesignFallback: false' in app and 'settings.showMap && snapshot.hasLiveRoute' in canvas,
 'lane arrows are shorter':'let bottom = h * 0.82' in canvas and 'let straightApexY = h * 0.12' in canvas,
 'large maneuver arrow unchanged':'size: CGFloat(34 * settings.maneuverArrowScale)' in canvas,
 'turn-only overlap preserved':'func turnOnlyCombined(right: Bool)' in canvas and 'straightArrow(inactiveColor)' in canvas,
 'thin lane control supported':'range: 0.60...2.50' in ui and 'max(0.45' in canvas,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('v90.35.3.21 failures:\n- '+'\n- '.join(failed))
print('v90.35.3.21 static checks passed:',len(checks))
