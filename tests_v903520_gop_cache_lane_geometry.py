#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parent
read=lambda r:(ROOT/r).read_text(encoding='utf-8')
video=read('ios/HUDController/MapMode/U2WMainVideoClient.swift')
canvas=read('ios/HUDController/MapMode/HudMapModeCanvas.swift')
app=read('ios/HUDController/App/AppState.swift')
ui=read('ios/HUDController/UI/NavigationHUDPreviewCard.swift')
cache=read('u2w/v8.21_PersistentGOPCache/source/u2w_mainvideo_cache.c')
stream=read('u2w/v8.21_PersistentGOPCache/source/u2w_mainvideo_streamer.c')
install=read('u2w/v8.21_PersistentGOPCache/source/install_once.sh')
checks={
 'cache daemon tails v8.11 live path':'/tmp/u2w_mainvideo_live.h264' in cache,
 'cache starts from validated IDR':'begin_cache_with_idr' in cache and 'sps_len' in cache and 'pps_len' in cache,
 'cache survives live generation change':'live-generation-change' in cache and 'same_generation' in cache,
 'streamer fails fast when cache absent':'Status: 503 Service Unavailable' in stream and 'Retry-After: 2' in stream,
 'streamer is fingerprinted':'X-U2W-Streamer: v8.21-gop-cache-relay' in stream,
 'streamer self-terminates if idle':'idle_polls>100' in stream,
 'installer leaves AppleCarPlay untouched':'pkill AppleCarPlay' not in install and 'killall AppleCarPlay' not in install and 'LD_PRELOAD' not in install,
 'app warms cache before map stream':'warmAdapterCache(reason:' in video and 'HUD BLE transport ready' in app,
 'app exposes cache status':'adapterCacheSummary' in video and 'U2W GOP cache' in ui,
 'no fake route preview':'allowDesignFallback: false' in app and 'settings.showMap && snapshot.hasLiveRoute' in canvas,
 'lane arrows are shorter':'let bottom = h * 0.82' in canvas and 'let straightApexY = h * 0.12' in canvas,
 'large maneuver arrow unchanged':'size: CGFloat(34 * settings.maneuverArrowScale)' in canvas,
 'turn-only overlap preserved':'func turnOnlyCombined(right: Bool)' in canvas and 'straightArrow(inactiveColor)' in canvas,
 'thin lane control supported':'range: 0.60...2.50' in ui and 'max(0.45' in canvas,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('v90.35.3.20 failures:\n- '+'\n- '.join(failed))
print('v90.35.3.20 static checks passed:',len(checks))
