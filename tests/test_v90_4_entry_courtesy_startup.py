from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MONITOR=(ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
VIEW=(ROOT/'ios/HUDController/UI/AmbientLightingView.swift').read_text()

def test_courtesy_power_is_just_an_individual_power_on_event_now():
    run=MONITOR.split('private func runStartupAnimationIfNeeded',1)[1].split('private func prepareAutomaticSyncMember',1)[0]
    assert 'guard obdEnginePowerSignalPresent else' in run
    assert 'Automatic Breath held until OBD connection' in run
    assert 'scheduleEngineStartupSynchronization(source: "GATT ready while OBD connected")' in run
    assert 'Automatic Breath withheld outside OBD-start/headlight cohort' in run

def test_ui_documents_simple_independent_behavior():
    assert 'Automatic Breath is OBD-gated' in VIEW
    assert 'headlight-ON transition animates only the newly powered cohort' in VIEW
    assert 'Door brightness is independent from animation and engine-session detection' in VIEW
