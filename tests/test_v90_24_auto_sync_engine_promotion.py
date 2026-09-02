from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift"
VIEW = ROOT / "ios/HUDController/UI/AmbientLightingView.swift"


def source(path):
    return path.read_text(encoding="utf-8")


def function_body(text: str, name: str, next_marker: str) -> str:
    start = text.index(name)
    end = text.index(next_marker, start)
    return text[start:end]


def test_courtesy_barrier_uses_only_physical_new_joiners_and_has_discovery_floor():
    m = source(MONITOR)
    barrier = function_body(
        m,
        "private func beginHeadlightTransitionSyncCohort",
        "private func registerPowerOnCohortMember",
    )
    assert "isPhysicallyPresentOrConnecting" in m
    assert "automaticHeadlightJoinEligible" in m
    assert "let joiningDevices = pairedDevices.filter { automaticHeadlightJoinEligible($0) }" in barrier
    assert "configured Door" in m and "must not hold a courtesy-light" in m
    assert "headlightSyncDiscoveryFloorSeconds: TimeInterval = 2.0" in m
    assert "syncBarrierCollectsNewJoiners = true" in barrier
    assert "physicalExpected=" in barrier


def test_automatic_lotus_shared_sync_has_no_visible_pre_t0_preparation():
    m = source(MONITOR)
    queue = function_body(m, "private func queuePowerUpBreath", "private func resetParticipantForHeadlightBarrier")
    assert "deferVisualPreparationForSync: Bool = false" in queue
    marker = "} else if deferVisualPreparationForSync {"
    start = queue.index(marker)
    end = queue.index("} else {", start + len(marker))
    deferred = queue[start:end]
    assert "isControllable" in deferred
    assert "no pre-T0 Power/RGB/brightness write" in deferred
    assert "sendPowerWhenReady" not in deferred
    assert "sendColorWhenReady" not in deferred
    assert "applyRuntimeBrightnessWhenReady" not in deferred


def test_raw_engine_on_owns_crank_window_and_suppresses_provisional_barrier():
    m = source(MONITOR)
    run = function_body(m, "private func runStartupAnimationIfNeeded", "private func queuePowerUpBreath")
    barrier = function_body(m, "private func beginHeadlightTransitionSyncCohort", "private func registerPowerOnCohortMember")
    hud = function_body(m, "func hudTransportPowerSignal", "func obdPowerSignal")
    assert "engineStartupSyncCandidateActive || engineStartupSyncPending" in run
    assert "Automatic Breath deferred to engine-start coordinator" in run
    assert "engineStartupSyncCandidateActive || engineStartupSyncPending" in barrier
    assert "Headlight sync barrier deferred to engine-start coordinator" in barrier
    assert "engineStartupSyncCandidateActive = true" in hud
    assert "supersedePendingHeadlightBarrierForEngineStartup" in hud


def test_confirmed_engine_start_promotes_all_enabled_roles_after_crank_and_gatt_settle():
    m = source(MONITOR)
    schedule = function_body(m, "private func scheduleEngineStartupSynchronization", "private func beginEngineStartupFullSyncCohort")
    full = function_body(m, "private func beginEngineStartupFullSyncCohort", "private func confirmEnginePowerOn")
    confirm = function_body(m, "private func confirmEnginePowerOn", "private func scheduleEnginePowerOffConfirmation")
    assert "engineStartupCrankSettleSeconds: TimeInterval = 4.0" in m
    assert "engineStartupBLEDIMQuietSeconds: TimeInterval = 1.5" in m
    assert "engineStartupMaxWaitSeconds: TimeInterval = 16.0" in m
    assert "$0.role != nil && $0.startupAnimationEnabled && $0.powerOn" in schedule
    assert "ready.count == eligible.count" in schedule
    assert "gattControlReadyAtByID" in schedule
    assert "animationPipelineIdle" in schedule
    assert "beginEngineStartupFullSyncCohort" in schedule
    assert "ENGINE-START FULL-COHORT opened" in full
    assert "deferVisualPreparationForSync: true" in full
    assert "isJoiningHeadlightTransition" not in full
    assert "scheduleEngineStartupSynchronization(source: source)" in confirm


def test_engine_off_rearms_startup_exception_but_later_headlight_rule_stays_new_joiners_only():
    m = source(MONITOR)
    off = function_body(m, "private func confirmEnginePowerOff", "private func evaluateVehicleLightingAutomation")
    view = source(VIEW)
    assert "engineStartupSyncCompletedForCurrentEngineSession = false" in off
    assert "re-arms the one-time engine-start synchronization promotion" in off
    assert "only lights newly joining the current startup/headlight transition" in view
    assert "A light that is already active stays untouched" in view
    assert "initial confirmed engine start is the one deliberate exception" in view
    assert "even if Dashboard was already on from courtesy lighting" in view


def test_manual_preview_remains_separate_from_automatic_deferred_prep():
    m = source(MONITOR)
    preview = function_body(m, "func previewEnabledBreathNow", "// MARK: - Finite configurable-color overspeed warning")
    assert "previewBreath(devices: devices)" in preview
    assert "queuePowerUpBreath(device.id, force: true)" in preview
    assert "deferVisualPreparationForSync" not in preview
    assert "Flight recorder v90.26 enabled" in m
    assert "autoSyncPrep=deferredToT0" in m
    assert "engineStartupPromotion=fullCohort" in m
