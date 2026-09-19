#!/usr/bin/env python3
"""Static regression checks for v90.35.3.13.2 field stabilization."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent

def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

video = text("ios/HUDController/MapMode/U2WMainVideoClient.swift")
app = text("ios/HUDController/App/AppState.swift")
proto = text("ios/HUDController/Protocol/HudProtocol.swift")
ble = text("ios/HUDController/Bluetooth/HudBluetoothManager.swift")
canvas = text("ios/HUDController/MapMode/HudMapModeCanvas.swift")

checks = {
    "5 fps physical HUD cadence remains unchanged": ".milliseconds(200)" in app,
    "decoder output stall watchdog is bounded": "decoderStaleFrameInterval: TimeInterval = 3.0" in video,
    "decoder-stale diagnostics remain bounded": "lastDecoderStaleDiagnosticAt" in video and "initialIDRWaitDiagnosticInterval" in video,
    "fresh bytes recover decoder without reconnecting TCP": "HARD decoder recovery, TCP preserved" in video and "bytesAreFresh" in video,
    "accepted decoder state survives HTTP reseed": "decoder.prepareForStreamRestart()" in video,
    "SPS/PPS candidates are staged separately": all(s in video for s in ("activeSPS", "activePPS", "pendingSPS", "pendingPPS")),
    "bad SPS/PPS cannot evict known-good decoder": "preserving last-known-good decoder" in video,
    "parameter sets are promoted only after VT session creation": "Atomic promotion: only now retire the prior VideoToolbox session." in video,
    "current HUD session requires client and live frame": "clientSeen && liveFrameSent" in app,
    "generic MJPEG established flag is diagnostic only": "ESTABLISHED socket can belong to the prior session" in app,
    "automatic viewer recovery is bounded": "hudU2WAutomaticViewerRecoveryCount == 0" in app,
    "automatic viewer recovery preserves STA credentials": "AUTO VIEWER RECOVERY mode4→mode6 only" in app and "preserving STA credentials" in app,
    "HUD wire parser validates exact escape followers": "decodedEscapeFollower" in proto and "Invalid escape follower" in proto,
    "OBD parser keeps exact raw capture before suppression": ble.find("captureOBDDiagnosticRawBLE(data)") < ble.find("shouldSuppressDuplicateDiagnosticBLEFragment(data)") < ble.find("self.logger.log(\"RX CHUNK\", self.lastRX)"),
    "duplicate continuation suppression is parser-only": "Suppressed duplicate BLE continuation fragment" in ble,
    "diagnostic chunks require exact declared length": "available == chunkSize" in ble,
    "returned CRUSH archive is retained": "LOG_CATEGORY_CRUSH" in ble and "Accepted returned diagnostic stream" in ble,
    "existing content-blind Map Mode crop remains": "sourceMapImage" in canvas and "HudMapModeSourceCrop" in canvas,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("v90.35.3.13.2 static check failures:\n- " + "\n- ".join(failed))

# Guard that this app-only stabilization release did not alter the bundled U2W v8.17 images.
expected = {
    "u2w/v8.17_LatestFrame/U2W_Update_v8.17_LatestFrame.img": "6313ac3ec24a8a44456ae18c0a8c7f4a05b39d573479aa72b8bbff844045b19b",
    "u2w/v8.17_LatestFrame/U2W_Update_v8.17_LatestFrame_UNINSTALL.img": "396524a1ce72ec7f39a555b054f5727e31260d6b331ed71e2f68fba2284d4ee3",
}
for rel, wanted in expected.items():
    digest = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
    if digest != wanted:
        raise SystemExit(f"U2W v8.17 image changed unexpectedly: {rel} {digest} != {wanted}")

print(f"v90.35.3.13.2 stabilization static checks passed: {len(checks) + len(expected)}")
