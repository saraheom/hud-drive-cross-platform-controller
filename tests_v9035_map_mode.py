from pathlib import Path

ROOT = Path(__file__).parent
APP = ROOT / "ios" / "HUDController"


def read(rel):
    return (ROOT / rel).read_text()


def test_map_mode_settings_and_component_controls():
    settings = read("ios/HUDController/Models/HudMapModeSettings.swift")
    for token in [
        "leftScale", "centerScale", "rightScale",
        "showSpeed", "showSpeedLimit", "showMap",
        "showTurningStreet", "showManeuver", "showDistance",
        "showLaneGuidance", "showETA", "showTimeLeft",
        "nativeOBDSpeedOverlayExperiment", "followSource", "darkHUD", "lightHUD",
    ]:
        assert token in settings, token


def test_us_speed_limit_and_right_widget_order():
    canvas = read("ios/HUDController/MapMode/HudMapModeCanvas.swift")
    assert 'Text("SPEED")' in canvas
    assert 'Text("LIMIT")' in canvas
    assert "usSpeedLimitSign" in canvas
    # Right widget code order must remain street -> maneuver -> distance -> lanes -> ETA/time.
    indices = [
        canvas.index("settings.showTurningStreet"),
        canvas.index("settings.showManeuver"),
        canvas.index("settings.showDistance"),
        canvas.index("settings.showLaneGuidance"),
        canvas.index("settings.showETA || settings.showTimeLeft"),
    ]
    assert indices == sorted(indices)


def test_kivic_cast_transport_and_restore():
    server = read("ios/HUDController/MapMode/HudMapModeCastServer.swift")
    state = read("ios/HUDController/App/AppState.swift")
    for token in ["KVMJPEG/1.0", "15320", "15330", "multipart/x-mixed-replace"]:
        assert token in server, token
    assert "HudCommands.kivicMode(5)" in state
    assert "HudCommands.kivicMode(4)" in state
    assert "restoreDashboardOperatingMode" in state
    assert "obd.applyWidgetSelection()" in state


def test_native_obd_speed_probe_is_real_item_10_and_custom_speed_is_blank():
    state = read("ios/HUDController/App/AppState.swift")
    canvas = read("ios/HUDController/MapMode/HudMapModeCanvas.swift")
    assert "HudOBDItem.drivingVelocity.rawValue" in state
    assert "position: 0" in state
    assert "suppressCustomSpeedForNativeOBDProbe" in canvas
    assert "Color.clear.frame(height: 60)" in canvas


def test_cold_off_never_sends_transient_true():
    state = read("ios/HUDController/App/AppState.swift")
    start = state.index("private func scheduleTimeWeatherColdOffSynchronization")
    end = state.index("/// Restore the normal dashboard/profile", start)
    block = state[start:end]
    assert "HudCommands.timeWeather(false)" in block
    assert "HudCommands.timeWeather(true)" not in block
    assert "no transient ON packet sent" in block


def test_u2w_route_metadata_exposed_for_map_mode():
    route = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    state = read("ios/HUDController/App/AppState.swift")
    assert "private(set) var timeRemainingSeconds = 0" in route
    assert "private(set) var routeRoads: [String] = []" in route
    assert "uniqueRouteRoads(from snapshot" in route
    assert "routeGuidance.timeRemainingSeconds" in state
    assert "routeGuidance.routeRoads" in state


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    print(f"v90.35 map-mode static checks passed: {len(tests)}")
