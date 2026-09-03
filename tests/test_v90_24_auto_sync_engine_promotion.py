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
    run = function_body(m, "private func runStartupAnimationIfNeeded", "private func prepareAutomaticSyncMember")
    barrier = function_body(m, "private func beginHeadlightTransitionSyncCohort", "private func registerPowerOnCohortMember")
    assert 'guard hudEnginePowerSignalPresent else' in run
    assert 'Automatic Breath held until HUD connection' in run
    assert 'guard hudEnginePowerSignalPresent else' in barrier
    assert 'let joiningDevices = pairedDevices.filter { automaticHeadlightJoinEligible($0) }' in barrier
    assert 'Door is enrolled only when Door itself is newly joining' in barrier

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
    hud = function_body(m, "func hudTransportPowerSignal", "func obdPowerSignal")
    obd = function_body(m, "func obdPowerSignal", "private func currentOBDTargetName")
    assert 'scheduleEngineStartupSynchronization(source: "HUD connected")' in hud
    assert 'engineStartupSyncCompletedForCurrentEngineSession = false' in hud
    assert 'Pending automatic sync cancelled because HUD disconnected' in hud
    assert 'scheduleEngineStartupSynchronization' not in obd
    assert 'diagnostic/corroborating state only' in obd

def test_confirmed_engine_start_promotes_all_enabled_roles_after_crank_and_gatt_settle():
    m = source(MONITOR)
    schedule = function_body(m, "private func scheduleEngineStartupSynchronization", "private func beginEngineStartupFullSyncCohort")
    full = function_body(m, "private func beginEngineStartupFullSyncCohort", "private func confirmEnginePowerOn")
    confirm = function_body(m, "private func confirmEnginePowerOn", "private func scheduleEnginePowerOffConfirmation")
    assert 'engineStartupMaxWaitSeconds: TimeInterval = 10.0' in m
    assert 'requiredRoles: Set<AmbientLightRole> = [.centerConsole, .door, .dashboard]' in schedule
    assert 'roles == requiredRoles' in schedule
    assert 'HUD STARTUP armed' in schedule
    assert 'HUD STARTUP FULL-COHORT opened' in full
    assert 'ready.count == 3' in full
    assert 'no partial/late Breath' in full
    assert 'deferVisualPreparationForSync: true' in m
    assert 'ambient animation remains gated exclusively by HUD transport connection' in confirm
    assert 'scheduleEngineStartupSynchronization(source: source)' not in confirm

def test_engine_off_rearms_startup_exception_but_later_headlight_rule_stays_new_joiners_only():
    m = source(MONITOR)
    hud = function_body(m, "func hudTransportPowerSignal", "func obdPowerSignal")
    view = source(VIEW)
    assert 'engineStartupSyncCompletedForCurrentEngineSession = false' in hud
    assert 'HUD disconnected' in hud
    assert 'Automatic Breath is HUD-connection-gated' in view
    assert 'Center + Door + Dashboard' in view
    assert 'Door is already on and Center + Dashboard turn on with the headlights' in view
    assert 'There is no late independent catch-up Breath' in view

def test_manual_preview_remains_separate_from_automatic_deferred_prep():
    m = source(MONITOR)
    preview = function_body(m, "func previewEnabledBreathNow", "// MARK: - Finite configurable-color overspeed warning")
    assert "previewBreath(devices: devices)" in preview
    assert "queuePowerUpBreath(device.id, force: true)" in preview
    assert "deferVisualPreparationForSync" not in preview
    assert "Flight recorder v90.29 enabled" in m
    assert "hudAnimationGate=1" in m
    assert "noLateCatchup=1" in m

