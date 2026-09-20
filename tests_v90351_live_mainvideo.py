from pathlib import Path
R=Path(__file__).resolve().parent

def read(rel): return (R/rel).read_text(errors='replace')

client=read('ios/HUDController/MapMode/U2WMainVideoClient.swift')
canvas=read('ios/HUDController/MapMode/HudMapModeCanvas.swift')
settings=read('ios/HUDController/Models/HudMapModeSettings.swift')
app=read('ios/HUDController/App/AppState.swift')
ui=read('ios/HUDController/UI/NavigationHUDPreviewCard.swift')
renderer=read('ios/HUDController/MapMode/HudMapModeFrameRenderer.swift')

checks=[]
def check(name, cond):
    if not cond: raise AssertionError(name)
    checks.append(name)

check('u2w endpoint', '192.168.50.2' in client and '15332' in client and 'U2WH2643' in client)
check('videotoolbox decoder', 'VideoToolbox' in client and 'CMVideoFormatDescriptionCreateFromH264ParameterSets' in client and 'VTDecompressionSessionDecodeFrame' in client)
check('no OCR/screenshare imports in main video client', 'import ScreenCaptureKit' not in client and 'GoogleMapsOCRParser' not in client)
check('source image enters canvas and renderer', 'sourceMapImage' in canvas and 'sourceMapImage' in renderer)
check('follow/dark/light real-pixel filtering', 'case .followSource' in canvas and '.brightness(-0.30)' in canvas and '.brightness(0.08)' in canvas)
check('crop persistence', all(x in settings for x in ['sourceMapZoom','sourceMapOffsetX','sourceMapOffsetY']))
check('live status UI', 'LabeledContent("MainVideo"' in ui and 'state.mainVideo.frameCount' in ui and 'Reconnect U2W video' in ui)
check('freeze before legacy wifi handoff', app.index('mapModeFrozenSourceImage = mainVideo.latestFrame') < app.index('mainVideo.stop(reason: "Map Mode HUD-Wi-Fi handoff'))
check('live map mode keeps background predecode warm', 'live U2W Map Mode disabled — keep continuous predecode alive' in app)
check('bundled u2w v811 image', (R/'u2w/v8.11_MainVideoLive/U2W_Update_v8.11_MainVideoLive.img').exists())

print(f'v90.35.1 live-mainvideo static checks passed: {len(checks)}')
