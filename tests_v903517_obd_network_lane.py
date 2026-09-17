from pathlib import Path

ROOT = Path(__file__).parent

def read(rel):
    return (ROOT / rel).read_text()


def test_obd_probe_is_separate_persistent_toggle():
    ui = read("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
    state = read("ios/HUDController/App/AppState.swift")
    start = ui.index("DisclosureGroup(isExpanded: $showMapCustomization)")
    end = ui.index("} label: {", start)
    custom = ui[start:end]
    assert "obdProbeControls" not in custom
    assert "Native OBD speed test" in ui
    assert "setHUDU2WNativeOBDSpeedProbeEnabled" in ui
    assert "hudU2WNativeOBDProbeEnabled" in state
    assert "remains active until toggle off" in state
    assert "12s two-phase probe complete" not in state


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
    assert '.frame(width: 14, height: 18)' in canvas
    assert 'Image(systemName: "arrow.up")' in canvas
    assert 'Image(systemName: "arrow.turn.up.right")' in canvas
    assert 'Image(systemName: "arrow.turn.up.left")' in canvas
    assert 'case 3:' in canvas and 'case 5:' in canvas
    assert 'return "arrow.up.right"' not in canvas
    assert 'return "arrow.up.left"' not in canvas


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    print(f"v90.35.3.17 static checks passed: {len(tests)}")
