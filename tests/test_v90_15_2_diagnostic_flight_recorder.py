from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_event_driven_ambient_flight_recorder_captures_v9017_runtime_state():
    assert 'private func ambientTrace(_ reason: String)' in MONITOR
    assert '"AMBIENT TRACE"' in MONITOR
    assert 'engineDiag{hud=' in MONITOR
    assert 'dayNight{raw=' in MONITOR
    assert 'breath{sync=' in MONITOR
    assert 'startup{complete=' not in MONITOR
    assert 'epoch=' not in MONITOR
    assert 'ambientRoleTraceState(.door)' in MONITOR
    assert 'ambientRoleTraceState(.dashboard)' in MONITOR
    assert 'ambientRoleTraceState(.centerConsole)' in MONITOR
    assert 'ops=' in MONITOR

def test_duplicate_headlight_advertisements_do_not_starve_stability_timer():
    block = MONITOR.split('private func scheduleHeadlightConsensusEvaluation', 1)[1].split('private func commitConfirmedHeadlightPower', 1)[0]
    assert 'headlightConsensusCandidate == candidate, headlightConsensusTask != nil' not in block  # implementation now has stronger combined dedupe
    assert 'if headlightConsensusCandidate == candidate' in block
    assert 'if headlightConsensusTask != nil { return }' in block
    assert 'AllowDuplicates enabled' in block
    assert 'repeated advertisements that report the SAME' in block


def test_v9017_removes_engine_startup_classifier_and_keeps_three_state_day_night_consensus():
    assert 'private func startupHeadlightConsensus' not in MONITOR
    assert 'private func finishVehicleStartupClassification' not in MONITOR
    assert 'private func tryStartVehicleStartupBreath' not in MONITOR
    block = MONITOR.split('private func currentHeadlightConsensus', 1)[1].split('private func scheduleHeadlightConsensusEvaluation', 1)[0]
    assert 'return .bothOn' in block
    assert 'return .bothOff' in block
    assert 'return .mixed' in block

def test_per_light_power_on_admission_is_logged_instead_of_engine_gated():
    assert 'Fresh power-on boot settle scheduled' in MONITOR
    assert 'Fresh power-on boot settle complete' in MONITOR
    assert 'Breath prepare queued' in MONITOR
    assert 'Breath participant ready' in MONITOR
    assert 'Independent Breath begin' in MONITOR
    assert 'Synchronized Breath begin' in MONITOR
    run = MONITOR.split('private func runStartupAnimationIfNeeded', 1)[1].split('private func queuePowerUpBreath', 1)[0]
    assert 'enginePowerPresent' not in run
    assert 'headlightPowerSessionActive' not in run

def test_restore_and_abort_paths_are_fully_diagnostic_but_single_shot():
    assert '"AMBIENT RESTORE"' in MONITOR
    assert 'Steady restore begin:' in MONITOR
    assert 'Steady restore complete:' in MONITOR
    assert 'One-shot animation-abort fail-safe scheduled' in MONITOR
    assert 'One-shot fail-safe yielded without restore' in MONITOR
    assert 'scheduleRobustSteadyStateRecovery' not in MONITOR
    assert 'rounds=3' not in MONITOR


def test_v9010_transport_is_still_untouched():
    assert 'protocolPacing=20Hz/rawBLEDIM' in MONITOR
    assert 'private var bledimSequenceByID: [UUID: UInt8]' in MONITOR
    assert 'private func sendPowerWhenReady' in MONITOR
    assert 'private func sendColorWhenReady' in MONITOR
    assert 'private func applyRuntimeBrightnessWhenReady' in MONITOR
    assert 'BLEDIM10Hz' not in MONITOR
