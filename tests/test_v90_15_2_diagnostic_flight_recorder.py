from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_event_driven_ambient_flight_recorder_captures_full_state():
    assert 'private func ambientTrace(_ reason: String)' in MONITOR
    assert '"AMBIENT TRACE"' in MONITOR
    assert 'engine{hud=' in MONITOR
    assert 'startup{complete=' in MONITOR
    assert 'headlight{raw=' in MONITOR
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


def test_startup_uses_three_state_consensus_and_never_maps_mixed_to_day():
    detector = MONITOR.split('private func startupHeadlightConsensus', 1)[1].split('private func doorTargetBrightness', 1)[0]
    assert 'return .bothOn' in detector
    assert 'return .bothOff' in detector
    assert 'return .mixed' in detector
    finish = MONITOR.split('private func finishVehicleStartupClassification()', 1)[1].split('private func applyCurrentDoorDayNightTarget', 1)[0]
    assert 'if observation == .mixed' in finish
    assert 'waiting for BOTH Dashboard + Center to agree' in finish
    assert 'startupClassificationCandidate != observation' in finish
    assert 'headlightConsensusStabilitySeconds' in finish
    assert 'let night = observation == .bothOn' in finish


def test_animation_admission_blockers_are_logged_instead_of_silent_returns():
    startup = MONITOR.split('private func tryStartVehicleStartupBreath', 1)[1].split('/// Record positive physical-power evidence', 1)[0]
    assert 'Vehicle-start Breath waiting' in startup
    assert 'doorGATTNotReady' in startup
    assert 'dashboardGATTNotReady' in startup
    assert 'centerGATTNotReady' in startup
    headlight = MONITOR.split('private func tryStartConfirmedHeadlightBreath', 1)[1].split('/// v90.15 vehicle-start admission', 1)[0]
    assert 'Consensus headlight Breath waiting' in headlight


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
