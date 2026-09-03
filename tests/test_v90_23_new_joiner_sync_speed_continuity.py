from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
VIEW = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()


def test_production_bledim_is_already_on_minimal_and_lab_ui_is_gone():
    prep = MONITOR.split("private func queuePowerUpBreath", 1)[1].split("private func registerPowerOnCohortMember", 1)[0]
    assert "? .alreadyOnMinimal" in prep
    minimal = prep.split("case .alreadyOnMinimal:", 1)[1].split("case .v9018NoFlash:", 1)[0]
    assert "sendPowerWhenReady" not in minimal
    assert "sendColorWhenReady" not in minimal
    assert "applyRuntimeBrightnessWhenReady" not in minimal
    terminal = MONITOR.split("private func finalizeBreathSteadyState", 1)[1].split("private func runStartupAnimationIfNeeded", 1)[0]
    assert "case .brightnessOnlyFinish, .alreadyOnMinimal, .v9018NoFlash:" in terminal
    assert "BLEDIM ANIMATION TEST LAB" not in VIEW
    assert "BLEDIM PRODUCTION ANIMATION" in VIEW
    assert "Already-On Minimal" in VIEW


def test_headlight_barrier_admits_only_newly_joining_lights():
    commit = MONITOR.split("private func commitConfirmedHeadlightPower", 1)[1].split("private func noteHeadlightPowerSeen", 1)[0]
    assert "if on, hudEnginePowerSignalPresent" in commit
    assert "beginHeadlightTransitionSyncCohort(reason: reason)" in commit
    barrier = MONITOR.split("private func beginHeadlightTransitionSyncCohort", 1)[1].split("private func registerPowerOnCohortMember", 1)[0]
    assert "let joiningDevices = pairedDevices.filter { automaticHeadlightJoinEligible($0) }" in barrier
    assert "let alreadyActiveDevices = pairedDevices.filter" in barrier
    assert "untouchedAlreadyActive" in barrier
    assert "joiningRoles.contains(.centerConsole) || joiningRoles.contains(.dashboard)" in barrier
    assert "HEADLIGHT STRICT-COHORT common T0" in barrier

def test_already_active_door_is_not_reset_or_prepared_by_headlight_barrier():
    barrier = MONITOR.split("private func beginHeadlightTransitionSyncCohort", 1)[1].split("private func registerPowerOnCohortMember", 1)[0]
    assert 'Door is enrolled only when Door itself is newly joining' in barrier
    assert 'already-on courtesy Door is never replayed' in barrier
    assert 'expectedDevicesByID' in barrier
    assert 'untouchedAlreadyActive' in barrier

def test_fresh_new_joiner_bledim_settles_before_common_t0():
    helper = MONITOR.split('private func prepareAutomaticSyncMember', 1)[1].split('private func queuePowerUpBreath', 1)[0]
    assert 'scheduleBLEDIMBootSettleReassert' in helper
    assert 'forceBreath: true' in helper
    barrier = MONITOR.split('private func beginHeadlightTransitionSyncCohort', 1)[1].split('private func registerPowerOnCohortMember', 1)[0]
    assert 'syncCohortExpectedIDs.isSubset(of: self.synchronizedBreathIDs)' in barrier
    assert 'HEADLIGHT STRICT-COHORT common T0' in barrier

def test_v9022_sync_migration_is_retained_in_v9024():
    assert 'HUD.Ambient.v90_22.headlightBarrierSyncMigrated' in MONITOR
    assert 'd.set(true, forKey: "HUD.Ambient.v90_17.syncPowerOnBreath")' in MONITOR
    assert 'self.synchronizePowerOnBreathEnabled = d.object(forKey: "HUD.Ambient.v90_17.syncPowerOnBreath")' in MONITOR
    assert "Flight recorder v90.30 enabled" in MONITOR
    assert 'startupSync=HUD-gated-all-three' in MONITOR
    assert 'headlightSync=new-joiners-strict' in MONITOR

def test_same_named_road_explicit_limit_hands_off_without_stale_gap():
    assert "private static func normalizedRoadIdentity" in SPEED
    assert '"jr": "junior"' in SPEED
    matcher = SPEED.split("private func bestImprovedTraceSpeedLimit", 1)[1].split("private func acceptImprovedLimit", 1)[0]
    assert "strongSameRoadCandidates" in matcher
    assert "$0.speedMph == currentSpeedLimitMph" in matcher
    assert "same-road fast handoff" in matcher
    assert "improvedPendingRoad = nil" in matcher
    assert "item.match.currentDistance <= 35" in matcher
    assert "item.match.currentAngle <= 35" in matcher
    assert "item.match.matchedPoints >= max(1, trace.count - 1)" in matcher
    assert "changedExplicit == nil" in matcher


def test_untagged_same_road_preserves_display_but_not_warning_freshness():
    matcher = SPEED.split("private func bestImprovedTraceSpeedLimit", 1)[1].split("private func acceptImprovedLimit", 1)[0]
    assert "$0.speedMph == nil" in matcher
    assert "improvedDisplayContinuityFresh = true" in matcher
    continuity = matcher.split("if improvedDisplayContinuityFresh, currentSpeedLimitMph > 0", 1)[1].split("return currentSpeedLimitMph", 1)[0]
    assert "acceptImprovedLimit" not in continuity
    assert "warning freshness unchanged" in continuity
    assert "improvedDisplayContinuityReason" in continuity
    assert "!improvedLastResolutionFresh," in SPEED
    assert "!improvedDisplayContinuityFresh," in SPEED
    assert "displayContinuity=%d" in SPEED
