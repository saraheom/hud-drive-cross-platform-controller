from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MONITOR=(ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
VIEW=(ROOT/'ios/HUDController/UI/AmbientLightingView.swift').read_text()

def test_courtesy_power_is_just_an_individual_power_on_event_now():
    run=MONITOR.split('private func runStartupAnimationIfNeeded',1)[1].split('private func queuePowerUpBreath',1)[0]
    assert 'enginePowerPresent' not in run
    assert 'let ownedByHeadlightBarrierNow = syncHeadlightBarrierActive' in run
    assert 'deferVisualPreparationForSync: ownedByHeadlightBarrierNow' in run
    assert 'every controller return is a brand-new power-on event' in MONITOR

def test_ui_documents_simple_independent_behavior():
    assert 'only lights newly joining the current startup/headlight transition' in VIEW
    assert 'Door brightness is independent from animation and engine-session detection' in VIEW
