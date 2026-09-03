from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
OBD = (ROOT / 'ios/HUDController/Vehicle/HudOBDController.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
DASH = (ROOT / 'ios/HUDController/UI/DashboardView.swift').read_text()


def block(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def test_hud_transport_is_only_automatic_animation_gate():
    hud = block(MONITOR, 'func hudTransportPowerSignal', 'func obdPowerSignal')
    obd = block(MONITOR, 'func obdPowerSignal', 'private func currentOBDTargetName')
    startup = block(MONITOR, 'private func scheduleEngineStartupSynchronization', 'private func beginEngineStartupFullSyncCohort')
    headlight = block(MONITOR, 'private func beginHeadlightTransitionSyncCohort', 'private func registerPowerOnCohortMember')
    assert 'scheduleEngineStartupSynchronization(source: "HUD connected")' in hud
    assert 'engineStartupSyncCompletedForCurrentEngineSession = false' in hud
    assert 'Pending automatic sync cancelled because HUD disconnected' in hud
    assert 'scheduleEngineStartupSynchronization' not in obd
    assert 'diagnostic/corroborating state only' in obd
    assert 'guard hudEnginePowerSignalPresent else' in startup
    assert 'guard hudEnginePowerSignalPresent else' in headlight
    assert 'hudAnimationGate=1' in MONITOR
    assert 'startupSync=HUD-gated-all-three' in MONITOR


def test_hud_startup_is_strict_three_light_common_t0():
    full = block(MONITOR, 'private func beginEngineStartupFullSyncCohort', 'private func confirmEnginePowerOn')
    assert 'ready == expectedNow, ready.count == 3' in full
    assert 'HUD STARTUP FULL-COHORT common T0 ready=3 late=0' in full
    assert 'no partial/late Breath' in full
    assert 'startIndividualBreathSession' not in full


def test_later_headlight_is_strict_new_joiners_only():
    headlight = block(MONITOR, 'private func beginHeadlightTransitionSyncCohort', 'private func registerPowerOnCohortMember')
    assert 'Door is enrolled only when Door itself is newly joining' in headlight
    assert 'untouchedAlreadyActive' in headlight
    assert 'for role in [AmbientLightRole.centerConsole, AmbientLightRole.dashboard]' in headlight
    assert 'HEADLIGHT STRICT-COHORT common T0' in headlight


def test_original_freeride_profile_and_active_mode_are_separate():
    assert 'center: "Simple"' in OBD
    assert 'navigationLayout: false' in OBD
    assert 'center: "Navigation"' in OBD
    assert 'navigationLayout: true' in OBD
    restore = block(APP, 'private func restoreDashboardOperatingMode', 'func updateSpotifyVehicleWakeGate')
    assert 'HudCommands.navigationState(false)' in restore
    assert 'Restore dashboard mode → Freeride (Navigation OFF)' in restore
    assert 'HudCommands.navigationState(true)' in restore
    assert 'navigation.sendCurrent()' not in restore
    # Both profile rehydration phases explicitly restore the active mode afterward.
    assert APP.count('restoreDashboardOperatingMode(reason:') >= 3  # declaration + phase 2 + phase 3


def test_no_periodic_freeride_hammer_and_no_unused_minimize_ui():
    assert 'freerideWatchdogTask' not in APP
    assert '20s display watchdog' not in APP
    assert 'DASHBOARD WATCHDOG' not in APP
    assert 'Toggle("Minimize widgets"' not in DASH


def test_v9028_speed_fixes_are_retained():
    assert 'pending same-limit source confirmation' in SPEED
    assert 'Pending same-limit confirmation — disable native warning threshold' in SPEED
    assert 'geometryType", value: "esriGeometryPoint"' in SPEED
    assert 'URLQueryItem(name: "distance", value: "650")' in SPEED
    assert 'pointRadius=650m rawFeatures=%d featuresWithSpeed=%d featuresWithGeometry=%d parsedSegments=%d' in SPEED
