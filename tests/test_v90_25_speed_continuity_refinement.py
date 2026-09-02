from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def matcher_body():
    return SPEED.split("private func bestImprovedTraceSpeedLimit", 1)[1].split("private func acceptImprovedLimit", 1)[0]


def test_v9025_keeps_v9024_ambient_baseline_and_identifies_release():
    assert "Flight recorder v90.27 enabled" in MONITOR
    assert "startupSync=OBD-gated-all-three" in MONITOR
    assert "headlightSync=new-joiners-strict" in MONITOR
    assert "noLateCatchup=1" in MONITOR


def test_close_aligned_same_road_successor_can_escape_aging_current_way_bonus():
    m = matcher_body()
    assert "v90.25 forward-successor escape hatch" in m
    assert "item.segment.elementID != improvedCurrentRoadID" in m
    assert "item.match.currentDistance <= 20" in m
    assert "item.match.currentAngle <= 20" in m
    assert "item.match.matchedPoints >= max(1, trace.count - 1)" in m
    assert "item.match.score <= min(2.75, best.match.score + 1.25)" in m
    assert "same-road successor fast handoff" in m
    assert "same-road successor untagged continuity" in m


def test_successor_continuity_still_refuses_to_mask_changed_explicit_speed():
    m = matcher_body()
    assert "let changedExplicit = continuityCandidates.first" in m
    changed = m.split("let changedExplicit = continuityCandidates.first", 1)[1].split("if changedExplicit == nil", 1)[0]
    assert "mph != currentSpeedLimitMph" in changed
    assert "if changedExplicit == nil" in m


def test_pending_explicit_same_limit_suppresses_stale_clear_for_one_confirmation_sample():
    m = matcher_body()
    assert 'improvedDisplayContinuityReason = "OSM pending same-limit road confirmation"' in m
    assert "best.speedMph == currentSpeedLimitMph" in m
    assert "confirmation=1/2; suppress stale display clear without refreshing warning freshness" in m
    assert "confirmation=\\(next)/2; suppress stale display clear without refreshing warning freshness" in m


def test_display_continuity_never_refreshes_warning_freshness():
    m = matcher_body()
    continuity = m.split("if improvedDisplayContinuityFresh, currentSpeedLimitMph > 0", 1)[1].split("improvedResolutionSource = confirmedOSM", 1)[0]
    assert "acceptImprovedLimit" not in continuity
    assert "improvedLastResolutionFresh = true" not in continuity
    assert "warning freshness unchanged" in continuity
    stale_gate = SPEED.split("if sourceMode == .improvedTracePhilly", 1)[1].split("// Warning requires", 1)[0]
    assert "!improvedDisplayContinuityFresh" in stale_gate


def test_continuity_reason_is_logged_separately_from_fresh_resolution():
    assert 'private var improvedDisplayContinuityReason = "none"' in SPEED
    assert 'improvedDisplayContinuityReason = "none"' in matcher_body()
    assert "display continuity active source=\\(improvedDisplayContinuityReason)" in matcher_body()
    assert "displayContinuity=%d" in SPEED
