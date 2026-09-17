from pathlib import Path

ROOT = Path(__file__).parent

def read(rel):
    return (ROOT / rel).read_text()


def test_obd_visual_probe_is_retired_from_active_map_mode():
    ui = read("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
    state = read("ios/HUDController/App/AppState.swift")
    assert "Native OBD speed test" not in ui
    assert "obdProbeControls" not in ui
    assert "suppressCustomSpeedForNativeOBDProbe: false" in state
    assert "native OBD overlay probe retired" in state

def test_network_logging_covers_default_wifi_and_cellular():
    video = read("ios/HUDController/MapMode/U2WMainVideoClient.swift")
    assert "import Network" in video
    assert 'NWPathMonitor(requiredInterfaceType: .wifi)' in video
    assert 'NWPathMonitor(requiredInterfaceType: .cellular)' in video
    assert '"IPHONE NETWORK"' in video
    assert "15s MainVideo heartbeat" in video
    assert "frameAge=" in video and "byteAge=" in video


def test_speed_limit_absence_has_no_rectangle_and_fixed_slot():
    canvas = read("ios/HUDController/MapMode/HudMapModeCanvas.swift")
    assert "settings.showSpeedLimit && snapshot.speedLimitMph > 0" in canvas
    assert "No OSM speed limit = no white rectangle" in canvas
    assert "Color.clear" in canvas
    assert 'Text("\\(snapshot.speedLimitMph)")' in canvas
    assert 'snapshot.speedLimitMph > 0 ?' not in canvas


def test_lane_pack_window_and_combined_turn_glyphs():
    canvas = read("ios/HUDController/MapMode/HudMapModeCanvas.swift")
    assert "private var displayedLaneValues" in canvas
    assert "guard values.count > 4 else { return values }" in canvas
    assert "activeInside" in canvas
    assert "LaneGuidanceGlyph(" in canvas
    assert ".frame(width: 15, height: 22)" in canvas
    assert "func combined(right: Bool)" in canvas
    assert "MergeManeuverGlyph" in canvas
    assert 'Image(systemName: "arrow.turn.up.right")' not in canvas
    assert 'Image(systemName: "arrow.turn.up.left")' not in canvas


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    print(f"v90.35.3.18 compatibility static checks passed: {len(tests)}")
