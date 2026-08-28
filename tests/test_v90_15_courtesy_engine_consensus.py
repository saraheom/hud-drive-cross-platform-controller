from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MONITOR=(ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()

def test_engine_diagnostics_can_remain_but_do_not_gate_ambient_power_on_animation():
    assert 'hudEnginePowerSignalPresent' in MONITOR
    run=MONITOR.split('private func runStartupAnimationIfNeeded',1)[1].split('private func queuePowerUpBreath',1)[0]
    assert 'enginePowerPresent' not in run
    assert 'vehicleStartupCompleted' not in run

def test_two_light_day_night_consensus_is_allowed_without_engine_gate():
    block=MONITOR.split('private func scheduleHeadlightConsensusEvaluation',1)[1].split('private func commitConfirmedHeadlightPower',1)[0]
    assert 'enginePowerPresent' not in block
    assert 'vehicleStartupCompleted' not in block
