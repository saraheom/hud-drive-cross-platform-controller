from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTE = (ROOT / "ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()


def test_v87_schema_is_optional_and_v86_compatible():
    assert "var laneGuidance: LaneGuidanceSnapshot?" in ROUTE
    assert "var laneGuidanceShowing: Bool" in ROUTE


def test_live_lane_normalization_covers_stock_five_shapes():
    assert "nativeLaneType(for angles: [Int])" in ROUTE
    for token in [".straightLeft", ".straightRight", ".left", ".right", ".straight"]:
        assert token in ROUTE
    assert "lane.recommended || lane.status == 2" in ROUTE


def test_live_lanes_are_cached_by_maneuver_index_before_activation():
    assert "liveLaneCacheByManeuver" in APP
    assert "state.laneManeuverIndex ?? state.currentManeuverIndex" in APP
    assert "liveLaneCacheByManeuver[currentIndex]" in APP
    assert "current maneuver" in APP


def test_live_lane_distance_drives_existing_near_turn_policy_without_restarting_every_poll():
    assert "updateActiveLaneDistanceMeters" in APP
    assert "wasVisible != isVisible" in APP
    assert "live distance threshold crossed" in APP
    assert "setLaneGuidanceForCurrentManeuver" in APP
    assert "laneGuidanceRefreshInterval" in APP


def test_live_lane_observability_is_explicit():
    for token in ["CARPLAY LANE RX", "CARPLAY LANE CACHE", "CARPLAY LANE CURSOR", "CARPLAY LANE ACTIVATE"]:
        assert token in ROUTE or token in APP
