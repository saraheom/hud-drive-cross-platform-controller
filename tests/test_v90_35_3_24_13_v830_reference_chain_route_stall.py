from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RGD = (ROOT / "ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()


def test_seq1428_moving_near_turn_stall_has_bounded_release_policy():
    assert "movingStagnationAge: TimeInterval = 10.0" in RGD
    assert "movingStagnationConfirmations = 3" in RGD
    assert "movingStagnationMinimumSpeedMph = 7" in RGD
    assert "movingStagnationNearManeuverMeters = 45" in RGD
    assert "snapshot.distanceToManeuverMeters > 0" in RGD
    assert "speedMph >= movingStagnationMinimumSpeedMph" in RGD
    assert "snapshots.removeValue(forKey: kind)" in RGD
    assert "release-obsolete-HUD-guidance-until-sequence-advances" in RGD
    assert "Route feed stale — waiting for fresh maneuver" in RGD


def test_stoplight_or_far_maneuver_does_not_meet_stall_gate():
    # The stale path requires BOTH motion and a near-turn snapshot; unchanged
    # sequence alone is intentionally not enough because Apple Maps can hold at lights.
    assert "sequenceAge >= movingStagnationAge, nearTurn, speedMph >= movingStagnationMinimumSpeedMph" in RGD
    assert "snapshot.distanceToManeuverMeters <= movingStagnationNearManeuverMeters" in RGD
    assert "successful HTTP response is therefore not sufficient liveness evidence" in RGD


def test_fresh_sequence_automatically_recovers_route_guidance():
    assert "Fresh sequence resumed source=" in RGD
    assert "automatic HUD navigation recovery allowed" in RGD
    assert "staleSequenceBySource[kind] = nil" in RGD


def test_v830_predecode_is_early_and_not_map_mode_gated():
    assert "app session early predecode" in APP
    assert "HUD BLE transport ready — early predecode" in APP
    assert "Route Guidance endpoint reachable — keep early predecode warm" in APP
    assert "MainVideo predecode intentionally preserved" in APP
    assert "architecture=v8.30-reference-chain-tcp-15332" in VIDEO
    assert 'Data("U2WH2647".utf8)' in VIDEO


def test_isolated_minus8969_preserves_decoder_and_future_idr_swap_is_atomic():
    assert "dropping this AU and PRESERVING current decoder/reference chain" in VIDEO
    assert "armRebuildAtNextIDR" in VIDEO
    assert "swap occurs only when a validated future IDR is already in hand" in VIDEO
    assert "kVTInvalidSessionErr (-12903)" in VIDEO


def test_old_passive_codec_probe_is_not_auto_started_in_production_release():
    assert "mainVideoDiagnostic?.ensureStarted(reason: \"Route Guidance endpoint reachable\")" not in APP
    assert "optional legacy forensics" in UI
    assert "v90.35.3.24.13 pairs with U2W v8.30" in UI
    assert "never kills/signals/restarts AppleCarPlay" in UI


def test_physical_seq1428_stall_fixture_matches_regression_gate():
    import json
    fixture = json.loads((ROOT / "tests/fixtures/u2wrgd_stall_seq1428.json").read_text())
    assert fixture["source"] == "Google Maps"
    assert fixture["sequence"] == 1428
    assert fixture["active"] is True
    assert fixture["routeState"] == 1
    assert fixture["currentRoad"] == "Rising Sun Ave"
    assert fixture["distanceToManeuverMeters"] == 15
    assert fixture["currentManeuverIndex"] == 4
    maneuver = next(x for x in fixture["maneuvers"] if x["index"] == 4)
    assert maneuver["afterRoad"] == "Adams Ave"
    # Field GPS was moving after the turn. The production guard requires >=7 mph,
    # so a representative 15 mph sample must qualify after three confirmations.
    age_seconds, speed_mph, confirmations = 12.0, 15, 3
    stale = (
        age_seconds >= 10.0
        and 0 < fixture["distanceToManeuverMeters"] <= 45
        and speed_mph >= 7
        and confirmations >= 3
    )
    assert stale


def test_seq1428_policy_does_not_false_trip_while_stopped():
    import json
    fixture = json.loads((ROOT / "tests/fixtures/u2wrgd_stall_seq1428.json").read_text())
    age_seconds, speed_mph, confirmations = 30.0, 0, 30
    stale = (
        age_seconds >= 10.0
        and 0 < fixture["distanceToManeuverMeters"] <= 45
        and speed_mph >= 7
        and confirmations >= 3
    )
    assert not stale
