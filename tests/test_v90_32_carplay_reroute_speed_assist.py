from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    return (ROOT / rel).read_text()


def test_maneuver_text_restores_original_without_debug_distance_suffix():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    maneuver = commands.split("static func maneuver(_ instruction: NavigationInstruction)", 1)[1].split("// MARK: - Original vehicle integration packets", 1)[0]
    assert "instruction.primaryText" in maneuver
    assert "instruction.streetName" in maneuver
    assert "instruction.currentStreet" in maneuver
    assert "primaryWithDistance" not in maneuver
    assert '• \\(exactDistance)' not in maneuver
    assert "distanceMeters" in maneuver


def test_first_current_maneuver_wins_and_no_maneuver_zero_fallback():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "primaryCurrentManeuver(in snapshot" in rg
    assert "snapshot.currentManeuverIndex" in rg
    assert "snapshot.nextManeuverIndex ?? snapshot.currentManeuverIndex" not in rg
    assert "?? snapshot.maneuvers.first" not in rg
    assert "index < 0xFFFF" in rg
    assert "The first index is the HUD's primary/current instruction" in rg


def test_reroute_holds_last_valid_until_new_current_maneuver_stabilizes():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "snapshot.routeState == 5" in rg
    assert "rerouteAwaitingFreshManeuver" in rg
    assert "rerouteCandidateConfirmations >= 2" in rg
    assert "instruction = lastValidInstruction" in rg
    assert "waiting for two progressive snapshots" in rg
    assert "rerouteGraceInterval: TimeInterval = 3.0" in rg
    assert "5→0→3→1" in rg
    assert "timed.snapshot.active && timed.snapshot.routeState != 0 || inRerouteGrace" in rg


def test_carplay_speed_assist_is_semantic_only_and_reroute_weakened():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    nav_models = read("ios/HUDController/Navigation/NavigationModels.swift")
    assert "struct CarPlayRouteContext" in nav_models
    assert "currentRoad" in nav_models and "nextRoad" in nav_models
    assert "This intentionally contains no posted-speed value" in nav_models
    assert "carPlayCurrentRoadScoreAdjustment" in speed
    assert "let full = context.isRouteTransition ? -0.15 : -1.25" in speed
    assert "match.currentAngle <= 45" in speed
    assert "match.currentAngle <= 70" in speed
    assert "sourceMode == .improvedTracePhilly" in speed
    assert "OSM/Philadelphia GIS remain the sole sources of posted-speed values" in speed


def test_carplay_road_normalization_handles_direction_and_street_abbreviations():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert '"n": "north"' in speed
    assert '"s": "south"' in speed
    assert '"e": "east"' in speed
    assert '"w": "west"' in speed
    assert '"st": "street"' in speed
    assert '"ave": "avenue"' in speed


def test_next_road_only_assists_completed_turn_geometry():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "carPlayNextRoadTakeoverAdjustment" in speed
    assert "context.distanceToManeuverMeters <= 180" in speed
    assert "match.currentDistance <= 20" in speed
    assert "match.currentAngle <= 25" in speed
    assert "!context.isRouteTransition" in speed


def test_waze_priority_is_unchanged_for_future_driving_test():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert 'case waze = "Waze"' in rg
    assert 'case .googleMaps: 300' in rg
    assert 'case .appleMaps: 200' in rg
    assert 'case .waze: 100' in rg
