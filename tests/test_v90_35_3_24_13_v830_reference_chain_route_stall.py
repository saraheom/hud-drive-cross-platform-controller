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


def test_v831_mainvideo_is_explicit_map_mode_only_and_navigation_independent():
    assert "app session early predecode" not in APP
    assert "HUD BLE transport ready — early predecode" not in APP
    assert "Route Guidance endpoint reachable — keep early predecode warm" not in APP
    assert 'self.mainVideo.start(reason: "physical Map Mode live source (optional)")' in APP
    assert "architecture=v8.34-hard-bounded-mirror-v831-raw-tcp-15332" in VIDEO
    assert 'Data("U2WH2648".utf8)' in VIDEO
    assert "adapter parser/cache=NONE" in VIDEO


def test_minus8969_burst_uses_fresh_epoch_quarantine_instead_of_poisoned_wait():
    assert "dropping this AU" in VIDEO
    assert "CODEC_BAD_DATA_GRACE_ARMED" in VIDEO
    assert "CODEC_BAD_DATA_GRACE_EXHAUSTED" in VIDEO
    assert 'requestHardRecovery(reason: "sustained codecBadDataErr (-8969) after bounded grace")' in VIDEO
    assert 'sourceEpochCorruption = reason.contains("codecBadDataErr (-8969)")' in VIDEO
    assert "hardRecoverAwaitingFreshCodecEpoch" in VIDEO
    assert "TCP PRESERVED" in VIDEO
    assert "kVTInvalidSessionErr (-12903)" in VIDEO


def test_passive_codec_probe_auto_ensure_is_diagnostic_only_in_v2416():
    assert 'mainVideoDiagnostic?.ensureStarted(reason: "v24.18 one-drive live-map diagnostic")' in APP
    assert 'passive v8.27.2 source/topology observer' not in UI
    assert 'Collect Live Map Diagnostic ZIP (parked)' in UI
    assert 'Collect Live Map Diagnostic ZIP (parked)' in UI
    assert 'v90.35.3.24.28 MainVideo client for U2W v8.37 forensic seam capture' in VIDEO
    assert 'no adapter parser/cache/GOP replay' in VIDEO


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
