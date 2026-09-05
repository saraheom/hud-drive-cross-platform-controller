from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text()


def test_u2w_v86_single_index_compatibility_promotes_only_when_primary_is_absent():
    route = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "private func primaryCurrentIndex(in snapshot: Snapshot)" in route
    assert "snapshot.currentManeuverIndices" in route
    assert "if let current = sanitizedCurrentIndex(snapshot.currentManeuverIndex)" in route
    assert "guard snapshot.currentManeuverIndex == nil" in route
    assert "let legacySingle = sanitizedCurrentIndex(snapshot.nextManeuverIndex)" in route
    assert "snapshot.maneuvers.contains(where: { $0.index == legacySingle })" in route
    # When both exported legacy fields exist, the second must still never replace
    # the real primary/current index.
    assert "if let current = sanitizedCurrentIndex(snapshot.currentManeuverIndex)" in route
    assert route.index("if let current = sanitizedCurrentIndex(snapshot.currentManeuverIndex)") < route.index("guard snapshot.currentManeuverIndex == nil")


def test_route_guidance_still_uses_endpoint_liveness_and_no_ocr_fallback():
    route = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "endpointStaleInterval: TimeInterval = 4.5" in route
    assert "An unchanged sequence simply means the route state did not change" in route
    assert "navigation.navigationOff(owner: .carPlayAdapter)" in route
    assert "ScreenCaptureKit" in route  # explicitly documented as excluded fallback


def test_untagged_shared_ref_corridor_bridges_the_displayed_limit():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "private static func sameRoadCorridor" in speed
    assert "let sharesRef = !lhsRef.isEmpty && lhsRef == rhsRef" in speed
    assert "corridorHighwayFamily(lhs.highway) == corridorHighwayFamily(rhs.highway)" in speed
    assert "takeover.speedMph == nil" in speed
    assert 'reason: "OSM connected road/ref corridor bridge"' in speed
    assert "bridgeImprovedRoadEpisode" in speed
    assert "preserve displayed %d mph via shared name/ref" in speed


def test_corridor_bridge_is_display_only_and_conflicting_explicit_speed_can_take_over():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    bridge = speed.split("private func bridgeImprovedRoadEpisode", 1)[1].split("private func bestImprovedTraceSpeedLimit", 1)[0]
    assert "improvedLastResolutionWarningEligible = false" in bridge
    assert "speedWarningThreshold(0)" in bridge
    # Only an untagged takeover can bridge. An explicit different limit therefore
    # falls through to the normal confirmed source path instead of inheriting the old one.
    matcher = speed.split("private func bestImprovedTraceSpeedLimit", 1)[1].split("private func acceptImprovedLimit", 1)[0]
    assert "takeover.speedMph == nil" in matcher
    assert "best.speedMph == nil" in matcher
    assert "improvedPendingLimit" in matcher


def test_same_number_explicit_reconfirmation_does_not_toggle_warning_threshold_off():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    accept = speed.split("private func acceptImprovedLimit", 1)[1].split("private static func resolvedKmh", 1)[0]
    assert "if warningEligible {" in accept
    assert "improvedLastResolutionWarningEligible = currentLimitWarningEligible" in accept
    assert "Pending inferred same-limit confirmation — disable native warning threshold" in accept
