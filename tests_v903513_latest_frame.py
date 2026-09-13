from pathlib import Path

ROOT = Path(__file__).resolve().parent

def read(rel):
    return (ROOT / rel).read_text(errors="replace")

client = read("ios/HUDController/MapMode/U2WMainVideoClient.swift")
app = read("ios/HUDController/App/AppState.swift")
canvas = read("ios/HUDController/MapMode/HudMapModeCanvas.swift")
settings = read("ios/HUDController/Models/HudMapModeSettings.swift")
ui = read("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
streamer = read("u2w/v8.17_LatestFrame/source/u2w_mainvideo_streamer.c")
installer = read("u2w/v8.17_LatestFrame/source/install_once.sh")


def check(name, condition):
    if not condition:
        raise AssertionError(name)


check("5fps relay cadence frozen", ".milliseconds(200)" in app)
check("content-blind crop wording", "Deliberately content-blind" in canvas and "Live CarPlay crop" in ui)
check("no OCR semantic gate", "ScreenCaptureKit" not in client and "OCR" in client and "configured rectangle" in client)
check("first-frame watchdog", "lastDecodedFrameAt ?? connectedAt" in client)
check("3s decode freshness", "decoderStaleFrameInterval: TimeInterval = 3.0" in client)
check("4s reconnect cooldown", "freshnessReconnectCooldown: TimeInterval = 4.0" in client)
check("access unit assembly", "pendingAccessUnit" in client and "firstMbInSliceIsZero" in client)
check("synchronous VideoToolbox", "VTDecodeFrameFlags(rawValue: 0)" in client and "enableAsynchronousDecompression" not in client)
check("fresh IDR after reset", "needsIDR = true" in client and "guard hasIDR else { return }" in client)
check("single frame mailbox", "Single-frame mailbox" in client and "self.latestFrame = image" in client)
check("right vertical spacing persistence", all(k in settings for k in [
    "streetToManeuverSpacing", "maneuverToLaneSpacing", "laneToETASpacing"
]))
check("right vertical spacing UI", all(k in ui for k in [
    "Street → maneuver", "Maneuver → lanes", "Lanes → ETA"
]))
check("right vertical spacing canvas", all(k in canvas for k in [
    "settings.streetToManeuverSpacing", "settings.maneuverToLaneSpacing", "settings.laneToETASpacing"
]))
check("generation tail fingerprint", "capture_tail" in streamer and "same_generation_at_pos" in streamer)
check("v817 marker requires v816", "/etc/u2w_v8_16_live_edge.marker" in installer)
check("v817 current-gop header", "v8.17-latest-frame-generation-guard" in streamer)

print("v90.35.3.13 latest-frame static checks passed: 16")
