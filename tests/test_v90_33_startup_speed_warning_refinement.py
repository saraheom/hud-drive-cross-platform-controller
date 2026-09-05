from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    return (ROOT / rel).read_text()


def test_route_liveness_is_endpoint_reachability_not_sequence_freshness():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "endpointStaleInterval: TimeInterval = 4.5" in rg
    assert "TimedSnapshot(snapshot: snapshot, receivedAt: now)" in rg
    assert "preRoadStartupStaleInterval" not in rg
    assert "freshnessInterval(for snapshot" not in rg


def test_route_policy_still_has_no_ocr_fallback():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    nav = read("ios/HUDController/Navigation/HudNavigationController.swift")
    assert "endpointStaleInterval: TimeInterval = 4.5" in rg
    assert "navigation.navigationOff(owner: .carPlayAdapter)" in rg
    assert "if owner == .ocr { return false }" in nav


def test_carplay_speed_bonus_is_geometry_gated_and_logs_raw_current_road():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "match.currentDistance <= 40, match.currentAngle <= 45" in speed
    assert "match.currentDistance <= 50, match.currentAngle <= 70" in speed
    assert "return 0" in speed
    assert r'"rgdCurrent=\(routeRoad.isEmpty ? "-" : routeRoad)' in speed
    assert 'of: "martin luther king junior "' in speed
    assert 'with: "martin luther king "' in speed


def test_state6_weakens_route_semantics_for_speed_matching():
    models = read("ios/HUDController/Navigation/NavigationModels.swift")
    assert "routeState == 3 || routeState == 5 || routeState == 6" in models


def test_overspeed_warning_has_separate_day_and_night_brightness():
    monitor = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    view = read("ios/HUDController/UI/VehicleView.swift")
    assert "overspeedWarningNightBrightness" in monitor
    assert 'HUD.Ambient.v90_33.overspeed.nightBrightness' in monitor
    assert "? 20" in monitor
    assert "warningIsNight = headlightPowerSessionActive" in monitor
    assert r'profile=\(warningIsNight ? "night" : "day")' in monitor
    assert "Day warning brightness" in view
    assert "Night warning brightness" in view


def test_overspeed_restore_interpolates_rgb_and_brightness_instead_of_snapping():
    monitor = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    assert "interpolatedOverspeedColor" in monitor
    assert "overspeedRestoreTransitionSeconds: TimeInterval = 1.0" in monitor
    assert "Smooth restore begin RGB=" in monitor
    assert "overspeed smooth RGB restore" in monitor
    assert "overspeed smooth brightness restore" in monitor
    assert "frame.isMultiple(of: 2)" in monitor
    assert "overspeed restore final RGB" in monitor
    assert "overspeed restore final brightness" in monitor
