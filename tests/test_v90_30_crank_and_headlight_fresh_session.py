from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
APPSTATE = (ROOT / "ios/HUDController/App/AppState.swift").read_text()


def block(start: str, end: str) -> str:
    return MONITOR.split(start, 1)[1].split(end, 1)[0]


def test_startup_waits_through_post_hud_crank_window_before_opening_all_three():
    assert 'hudStartupStabilizationSeconds: TimeInterval = 5.0' in MONITOR
    schedule = block('private func scheduleEngineStartupSynchronization', 'private func beginEngineStartupFullSyncCohort')
    assert 'HUD STARTUP stabilization armed' in schedule
    assert 'Task.sleep(for: .seconds(self.hudStartupStabilizationSeconds))' in schedule
    assert 'HUD STARTUP stabilization complete' in schedule
    assert 'beginEngineStartupFullSyncCohort' in schedule
    assert 'requiredRoles: Set<AmbientLightRole> = [.centerConsole, .door, .dashboard]' in schedule


def test_headlight_off_invalidates_stale_dashboard_session_and_forces_reconnect():
    helper = block('private func armDashboardForFreshHeadlightCycle', 'private func commitConfirmedHeadlightPower')
    assert 'minimumFreshHeadlightConnectionGenerationByID[dashboardID] = currentGeneration + 1' in helper
    assert 'animatedConnectionSession.remove(dashboardID)' in helper
    assert 'central.cancelPeripheralConnection(peripheral)' in helper
    commit = block('private func commitConfirmedHeadlightPower', 'private func noteHeadlightPowerSeen')
    assert 'if !on {' in commit
    assert 'armDashboardForFreshHeadlightCycle(reason: reason)' in commit


def test_strict_cohort_requires_fresh_generation_and_preserves_expected_member_across_delayed_disconnect():
    prepare = block('private func prepareAutomaticSyncMember', 'private func resetParticipantForHeadlightBarrier')
    assert 'minimumFreshHeadlightConnectionGenerationByID[id]' in prepare
    assert '(ambientConnectionGenerationByID[id] ?? 0) < requiredGeneration' in prepare
    assert 'Strict headlight cohort waiting for fresh physical reconnect' in prepare
    remove = block('private func removeFromActiveBreath', '// A controller may disappear while a sync cohort')
    assert 'preserveStrictExpectedMembership' in remove
    assert 'if !preserveStrictExpectedMembership' in remove
    assert 'preserving expected membership for reconnect' in remove


def test_fresh_connection_generation_is_incremented_on_real_didconnect():
    connect = block('didConnect peripheral: CBPeripheral', 'nonisolated func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect')
    assert 'let generation = (self.ambientConnectionGenerationByID[id] ?? 0) + 1' in connect
    assert 'self.ambientConnectionGenerationByID[id] = generation' in connect
    assert 'Fresh physical reconnect requirement satisfied' in connect


def test_headlight_strict_wait_is_wide_enough_for_field_observed_dashboard_reconnect():
    assert 'headlightStrictReadyTimeoutSeconds: TimeInterval = 15.0' in MONITOR
    assert 'HEADLIGHT STRICT-COHORT common T0' in MONITOR
    assert 'no partial/late Breath' in MONITOR


def test_startup_owns_door_target_without_independent_fade():
    door = block('private func applyCurrentDoorDayNightTarget', 'private func transitionDoorBrightness')
    assert 'engineStartupSyncTask != nil || engineStartupSyncPending' in door
    assert 'no independent fade' in door


def test_v9029_freeride_restore_and_v9028_speed_fixes_remain_present():
    assert 'Restored original Freeride active mode via Navigation OFF after profile rehydration' in APPSTATE
    assert 'pending same-limit road confirmation' in SPEED
    assert 'rawFeatures=' in SPEED
    assert 'esriGeometryPoint' in SPEED
    assert 'URLQueryItem(name: "distance", value: "650")' in SPEED


def test_release_marker_identifies_v9030():
    assert 'Flight recorder v90.30 enabled' in MONITOR
    assert 'hudStartupStabilization=' in MONITOR
    assert 'headlightSync=new-joiners-strict-fresh-dashboard' in MONITOR
