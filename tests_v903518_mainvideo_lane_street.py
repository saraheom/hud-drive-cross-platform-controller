#!/usr/bin/env python3
"""Static release guards for HUD v90.35.3.18 + U2W v8.20."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

video = read("ios/HUDController/MapMode/U2WMainVideoClient.swift")
canvas = read("ios/HUDController/MapMode/HudMapModeCanvas.swift")
ui = read("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
app = read("ios/HUDController/App/AppState.swift")
streamer = read("u2w/v8.20_ValidatedGOPBootstrap/source/u2w_mainvideo_streamer.c")
installer = read("u2w/v8.20_ValidatedGOPBootstrap/source/install_once.sh")

checks = {
    "isolated VT errors continue without forced IDR": "CONTINUE without IDR reset" in video,
    "consecutive-error rebuild threshold is bounded": "consecutiveErrorRebuildThreshold = 5" in video,
    "20s watchdog is nondestructive": "KEEP decoder session and continue validated P-frames" in video,
    "90s watchdog requests one live-edge reseed": "decoderLiveEdgeReseedInterval: TimeInterval = 90.0" in video and "validated-GOP HTTP reseed" in video,
    "old local resync hook is gone": "requestDecoderResync" not in video,
    "v8.20 response is fingerprinted": "X-U2W-Streamer: v8.20-validated-gop-bootstrap" in streamer,
    "v8.20 validates SPS profile": "plausible_sps_profile" in streamer,
    "v8.20 validates parameter-set/IDR proximity": "(*last_pps-*last_sps)>4096" in streamer and "(start-*last_pps)>65536" in streamer,
    "v8.20 does not hook AppleCarPlay": "AppleCarPlay" not in installer and "LD_PRELOAD" not in installer,
    "lane arrows use vectors": "LaneGuidanceGlyph" in canvas and "func combined(right: Bool)" in canvas,
    "combined arrows share a mid-shaft branch": "branchStartY = h * 0.56" in canvas,
    "merge maneuver vectors are available": "MergeManeuverGlyph" in canvas and "mergeManeuverKind" in canvas,
    "lane window retains readable four lanes": "guard values.count > 4 else { return values }" in canvas and "activeInside" in canvas,
    "turning street reserves exactly two lines": ".lineLimit(2)" in canvas and "minHeight: 29, maxHeight: 29" in canvas,
    "item10 UI is retired": "Native OBD speed test" not in ui,
    "active map mode never suppresses custom speed for item10": "suppressCustomSpeedForNativeOBDProbe: false" in app,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("v90.35.3.18 static failures:\n- " + "\n- ".join(failed))
print(f"v90.35.3.18 static checks passed: {len(checks)}")
