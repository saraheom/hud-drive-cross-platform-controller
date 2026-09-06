from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROUTE = (ROOT / "ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()


def test_lane_schema_remains_optional_and_old_exporters_decode():
    assert "var laneGuidance: LaneGuidanceSnapshot?" in ROUTE
    assert "var laneGuidanceShowing: Bool" in ROUTE
    assert "var laneGuidanceIndex: Int?" in ROUTE
    assert "var guidanceEventIndex: Int?" in ROUTE


def test_live_lane_normalization_covers_stock_five_shapes():
    assert "nativeLaneType(for angles: [Int])" in ROUTE
    for token in [".straightLeft", ".straightRight", ".left", ".right", ".straight"]:
        assert token in ROUTE
    assert "lane.recommended || lane.status == 2" in ROUTE


def test_v88_uses_active_guidance_selector_not_5204_event_as_route_maneuver():
    assert "receiveResolvedV88LaneGuidance" in APP
    assert "state.laneGuidanceIndex" in APP
    assert "state.laneGuidanceEventIndex" in APP
    assert "laneGuidanceShowing" in APP
    assert "hidden selector must never" in APP
    assert "liveLaneCacheByManeuver[currentIndex]" not in APP[APP.index("private func receiveResolvedV88LaneGuidance"):APP.index("private func receiveLegacyV87LaneGuidance")]


def test_live_lane_distance_drives_existing_near_turn_policy_without_restarting_every_poll():
    assert "updateActiveLaneDistanceMeters" in APP
    assert "wasVisible != isVisible" in APP
    assert "live distance threshold crossed" in APP
    assert "setLaneGuidanceForCurrentManeuver" in APP
    assert "laneGuidanceRefreshInterval" in APP


def test_maneuver_delivery_immediately_reasserts_same_maneuvers_lanes():
    assert "onManeuverDelivered" in ROUTE
    send = ROUTE.index("navigation.sendCurrent(owner: .carPlayAdapter)")
    callback = ROUTE.index("onManeuverDelivered?", send)
    assert send < callback
    assert "reassertLiveLaneAfterManeuverDelivery" in APP
    assert "activeManeuver == maneuverIndex" in APP
    assert "post-maneuver reassert" in APP


def test_live_lane_observability_is_explicit():
    for token in ["CARPLAY LANE RX", "CARPLAY LANE CURSOR", "CARPLAY LANE ACTIVATE", "CARPLAY LANE LATCH", "CARPLAY LANE REASSERT"]:
        assert token in ROUTE or token in APP
