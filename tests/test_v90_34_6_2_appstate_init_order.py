from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ios/HUDController/App/AppState.swift"

def test_live_lane_callback_registered_after_ambient_light_initialization():
    text = APP.read_text()
    ambient = text.index("self.ambientLight = ambientLight")
    callback = text.index("routeGuidance.onLaneGuidanceChanged =")
    assert ambient < callback
