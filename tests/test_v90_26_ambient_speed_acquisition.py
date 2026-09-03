from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()


def test_headlight_barrier_waits_for_admitted_live_member_preparation():
    barrier = MONITOR.split('private func beginHeadlightTransitionSyncCohort', 1)[1].split('private func registerPowerOnCohortMember', 1)[0]
    assert 'headlightStrictReadyTimeoutSeconds: TimeInterval = 15.0' in MONITOR
    assert 'syncCohortExpectedIDs.isSubset(of: self.synchronizedBreathIDs)' in barrier
    assert 'HEADLIGHT STRICT-COHORT skipped' in barrier
    assert 'no partial/late Breath' in barrier
    assert 'HEADLIGHT STRICT-COHORT common T0' in barrier

def test_absent_persistent_connect_request_is_not_physical_cohort_membership():
    physical = MONITOR.split('private func isPhysicallyPresentOrConnecting', 1)[1].split('private func isAdmittedSyncMemberStillPreparing', 1)[0]
    assert 'connectionStartedByID[id] != nil' not in physical
    assert 'peripheral.state == .connecting' in physical
    assert 'lastSeenByID[id]' in physical
    assert 'headlightRecentEvidenceSeconds' in physical


def test_engine_start_keeps_post_crank_reacquisition_window_open():
    assert 'engineStartupMaxWaitSeconds: TimeInterval = 10.0' in MONITOR
    assert 'HUD STARTUP stabilization armed' in MONITOR
    assert 'wait through crank/accessory disturbance' in MONITOR
    assert 'HUD STARTUP FULL-COHORT common T0 ready=3 late=0' in MONITOR
    assert 'strict all-three readiness not met' in MONITOR

def test_philly_uses_current_street_centerline_speed_layer():
    assert 'TRANSPORTATION_street_segment/FeatureServer/0/query' in SPEED
    assert 'POSTED_SPEED_LIMIT' in SPEED
    assert 'SPEED_LIMIT' in SPEED
    assert 'FULL_STREET_NAME' in SPEED
    assert 'BUILT_STATUS=2' in SPEED
    assert 'SpeedLimits/FeatureServer' in SPEED  # retained only in historical explanatory comment
    provider = SPEED.split('private func fetchPhiladelphiaStreetCenterlines', 1)[1].split('// These helpers', 1)[0]
    assert 'services8.arcgis.com/6pr2WaSuWO79zliF' not in provider


def test_completed_turn_can_take_over_road_identity_from_sticky_trace_history():
    matcher = SPEED.split('private func bestImprovedTraceSpeedLimit', 1)[1].split('private func acceptImprovedLimit', 1)[0]
    assert 'completed-turn road takeover' in matcher
    assert 'currentCandidate!.match.currentAngle >= 45' in matcher
    assert 'item.match.currentDistance <= 12' in matcher
    assert 'item.match.currentAngle <= 20' in matcher
    assert 'improvedSameRoadContinuityArmed = false' in matcher
    assert 'improvedPendingLimit = nil' in matcher
    assert 'currentLimitWarningEligible = false' in matcher
    assert 'speedLimitAvailableForWarning = false' in matcher


def test_philly_current_geometry_fast_acquisition_ignores_old_trace_inertia_safely():
    matcher = SPEED.split('private func bestImprovedTraceSpeedLimit', 1)[1].split('private func acceptImprovedLimit', 1)[0]
    assert 'gisCurrentGeometryBest' in matcher
    assert 'item.match.currentDistance <= 12' in matcher
    assert 'item.match.currentAngle <= 20' in matcher
    assert 'location.speed >= 1.5' in matcher
    assert 'Philadelphia Street Centerline fast acquisition' in matcher


def test_untagged_new_road_can_use_unanimous_osm_corridor_consensus_display_only():
    assert 'private func sameRoadOSMSpeedConsensus' in SPEED
    assert 'observations.count >= 2' in SPEED
    assert 'values.count == 1' in SPEED
    assert 'same-road corridor consensus withheld' in SPEED
    matcher = SPEED.split('private func bestImprovedTraceSpeedLimit', 1)[1].split('private func acceptImprovedLimit', 1)[0]
    assert 'source: "OSM same-road corridor consensus"' in matcher
    assert 'warningEligible: false' in matcher


def test_v9025_continuity_safety_remains_after_new_road_changes():
    matcher = SPEED.split('private func bestImprovedTraceSpeedLimit', 1)[1].split('private func acceptImprovedLimit', 1)[0]
    assert 'same-road successor fast handoff' in matcher
    assert 'OSM pending same-limit road confirmation' in matcher
    assert 'warning freshness unchanged' in matcher
