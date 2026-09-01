from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
VIEW = (ROOT / 'ios/HUDController/UI/AmbientLightingView.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()


def test_every_disconnect_rearms_next_controller_return_immediately():
    assert 'every controller return is a brand-new power-on event' in MONITOR
    assert 'animatedConnectionSession.remove(id)' in MONITOR
    reset = MONITOR.split('private func scheduleStartupSessionReset', 1)[1].split('// MARK: - Fast Center-driven day/night + diagnostic two-light cross-check', 1)[0]
    assert '15' not in reset
    assert 'Power-on animation re-armed immediately after disconnect' in reset


def test_power_on_animation_is_not_gated_by_engine_or_headlight_state():
    run = MONITOR.split('private func runStartupAnimationIfNeeded', 1)[1].split('private func queuePowerUpBreath', 1)[0]
    assert 'enginePowerPresent' not in run
    assert 'vehicleStartupCompleted' not in run
    assert 'headlightPowerSessionActive' not in run
    assert 'scheduleBLEDIMBootSettleReassert' in run
    assert 'let ownedByHeadlightBarrierNow = syncHeadlightBarrierActive' in run
    assert 'deferVisualPreparationForSync: ownedByHeadlightBarrierNow' in run


def test_bledim_waits_for_boot_then_runs_one_complete_power_on_sequence():
    block = MONITOR.split('private func scheduleBLEDIMBootSettleReassert', 1)[1].split('private func animationWriteInterval', 1)[0]
    assert 'bledimBootSettleDelaySeconds' in block
    assert 'Fresh power-on boot settle scheduled' in block
    assert 'admitting Already-On Minimal Breath' in block
    assert 'self.queuePowerUpBreath(id, force: forceBreath)' in block
    assert 'restoreDeviceState(id)' not in block


def test_sync_is_optional_and_late_devices_get_complete_independent_breath():
    assert 'var synchronizePowerOnBreathEnabled: Bool' in MONITOR
    assert 'HUD.Ambient.v90_17.syncPowerOnBreath' in MONITOR
    prep = MONITOR.split('private func queuePowerUpBreath', 1)[1].split('private func startIndividualBreathSession', 1)[0]
    assert 'if !self.synchronizePowerOnBreathEnabled' in prep
    assert 'self.startIndividualBreathSession(id)' in prep
    assert 'Power-on cohort opened discovery=' in prep
    assert 'Power-on cohort already started; running complete independent Breath' in prep
    assert 'Toggle("Synchronize headlight/startup Breaths"' in VIEW


def test_independent_breath_has_complete_final_restore():
    block = MONITOR.split('private func startIndividualBreathSession', 1)[1].split('private func startSynchronizedBreathSession', 1)[0]
    assert 'Independent breath begin' in block
    assert 'independent power-up breath' in block
    assert 'finalizeBreathSteadyState(id, target: returnTarget)' in block
    assert 'ended with failed terminal commit' in block
    assert 'Breath terminal steady commit failed' in block


def test_fast_center_day_night_is_separate_from_animation_and_engine():
    schedule = MONITOR.split('private func scheduleHeadlightConsensusEvaluation', 1)[1].split('private func commitConfirmedHeadlightPower', 1)[0]
    assert 'enginePowerPresent' not in schedule
    assert 'vehicleStartupCompleted' not in schedule
    assert 'Dashboard+Center diagnostic consensus' in schedule
    commit = MONITOR.split('private func commitConfirmedHeadlightPower', 1)[1].split('private func noteHeadlightPowerSeen', 1)[0]
    assert 'Fast Center day/night' in commit
    assert 'beginHeadlightTransitionSyncCohort(reason: reason)' in commit
    assert 'tryStartConfirmedHeadlightBreath' not in commit
    assert 'applyCurrentDoorDayNightTarget' in commit
    assert 'Center presence → Auto brightness ON' in commit
    assert 'Center absence → Auto brightness OFF' in commit


def test_door_target_does_not_start_fade_during_bledim_boot_or_breath_prepare():
    block = MONITOR.split('private func applyCurrentDoorDayNightTarget', 1)[1].split('private func transitionDoorBrightness', 1)[0]
    assert 'bledimBootSettleTasks[doorID] != nil' in block
    assert 'breathPrepareTasks[doorID] != nil' in block
    assert 'activeBreathReturnBrightness[doorID] = target' in block


def test_abort_failsafe_remains_one_shot_and_not_headlight_gated():
    block = MONITOR.split('private func scheduleAnimationAbortFailsafe', 1)[1].split('private func scheduleBLEDIMBootSettleReassert', 1)[0]
    assert 'Task.sleep(for: .milliseconds(180))' in block
    assert 'self.restoreDeviceState(id)' in block
    assert 'confirmedHeadlightOff' not in block
    assert 'rounds=3' not in MONITOR


def test_osm_trace_logs_replayable_gps_path_candidates_and_decisions():
    assert '"OSM TRACE GPS"' in SPEED
    assert 'lat=%.6f lon=%.6f' in SPEED
    assert '"OSM TRACE PATH"' in SPEED
    assert 'points=[' in SPEED
    assert '"OSM TRACE MATCH"' in SPEED
    assert 'currentDistance' in SPEED and 'currentAngle' in SPEED and 'matchedPoints' in SPEED
    assert 'name=%@ ref=%@ highway=%@ limit=%d score=%.2f dist=%.1fm angle=%.1f' in SPEED
    assert 'seg=%.6f,%.6f>%.6f,%.6f' in SPEED
    assert 'speedTags=%@/%@/%@' in SPEED
    assert '"OSM TRACE OUTPUT"' in SPEED
    assert '"OSM TRACE DECISION"' in SPEED
    assert 'new pending way=' in SPEED
    assert 'confirm pending way=' in SPEED
    assert 'reject switch way=' in SPEED
    assert 'retain current way=' in SPEED


def test_door_day_night_is_event_driven_not_reapplied_by_half_second_watchdog():
    watchdog = MONITOR.split('private func startWatchdog()', 1)[1]
    assert 'evaluateVehicleLightingAutomation()' not in watchdog
    assert 'Center-driven watchdog reasserted HUD auto brightness' in watchdog


def test_same_door_fade_target_cannot_cancel_and_restart_itself():
    assert 'private var brightnessTransitionTargetByID: [UUID: Int]' in MONITOR
    block = MONITOR.split('private func applyCurrentDoorDayNightTarget', 1)[1].split('private func transitionDoorBrightness', 1)[0]
    assert 'brightnessTransitionTasks[doorID] != nil' in block
    assert 'brightnessTransitionTargetByID[doorID] == target' in block


def test_door_breath_rereads_day_night_target_after_prepare_window():
    prep = MONITOR.split('private func queuePowerUpBreath', 1)[1].split('private func startIndividualBreathSession', 1)[0]
    assert 'let returnBrightness: Int' in prep
    assert 'self.steadyBrightnessTarget(for: latestDevice)' in prep
    assert 'self.activeBreathReturnBrightness[id] = returnBrightness' in prep


def test_failed_terminal_commit_cannot_be_silently_treated_as_success():
    independent = MONITOR.split('private func startIndividualBreathSession', 1)[1].split('private func startSynchronizedBreathSession', 1)[0]
    assert 'if !sent {' in independent
    assert 'scheduleAnimationAbortFailsafe(for: id, reason: "Breath terminal steady commit failed")' in independent
    sync = MONITOR.split('private func startSynchronizedBreathSession', 1)[1].split('private func breathBrightnessFraction', 1)[0]
    assert 'failedTerminalCommits' in sync
    assert 'Synchronized Breath terminal steady commit failed' in sync


def test_group_fade_cancellation_cleans_every_shared_owner():
    assert 'private var brightnessTransitionTokenByID: [UUID: UUID]' in MONITOR
    cancel = MONITOR.split('private func cancelBrightnessTransition', 1)[1].split('private func scheduleAnimationAbortFailsafe', 1)[0]
    assert 'affectedIDs' in cancel
    assert 'brightnessTransitionTokenByID.compactMap' in cancel
    assert 'brightnessTransitionTasks[affectedID] = nil' in cancel
    transition = MONITOR.split('private func transitionBrightness', 1)[1].split('// MARK: - Packet adapters', 1)[0]
    assert 'let transitionToken = UUID()' in transition
    assert 'defer {' in transition


def test_osm_trace_held_sign_does_not_refresh_fresh_resolution_clock():
    assert 'private var traceLastResolutionFresh = false' in SPEED
    assert 'case .traceOSM:' in SPEED and 'resolutionIsFresh = traceLastResolutionFresh' in SPEED
    assert 'if resolutionIsFresh {' in SPEED
    assert 'fresh=%d' in SPEED
    trace = SPEED.split('private func bestTraceSpeedLimit', 1)[1].split('private static func resolvedKmh', 1)[0]
    assert 'traceLastResolutionFresh = false' in trace
    assert trace.count('traceLastResolutionFresh = true') >= 2


def test_vehicle_help_text_matches_fast_center_hud_brightness_owner():
    vehicle = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()
    assert 'Use Center/BLEDOM power for HUD Auto Brightness' in vehicle
    assert 'Center present = night/Auto Brightness ON' in vehicle
    assert 'Dashboard cannot delay either output' in vehicle
