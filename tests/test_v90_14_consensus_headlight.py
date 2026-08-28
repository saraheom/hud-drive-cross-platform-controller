from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
SPOTIFY = (ROOT / 'ios/HUDController/Media/SpotifyMediaController.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
VIEW = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()

def test_headlight_requires_stable_two_controller_consensus():
    assert 'private enum HeadlightConsensusObservation' in MONITOR
    assert 'case bothOn' in MONITOR and 'case bothOff' in MONITOR and 'case mixed' in MONITOR
    assert 'headlightConsensusStabilitySeconds: TimeInterval = 0.75' in MONITOR
    assert 'both Center + Dashboard stable ON' in MONITOR
    assert 'both Center + Dashboard stable OFF' in MONITOR
    assert 'preserving confirmed' in MONITOR

def test_headlight_consensus_no_longer_owns_animation():
    commit = MONITOR.split('private func commitConfirmedHeadlightPower', 1)[1].split('private func noteHeadlightPowerSeen', 1)[0]
    assert 'Two-light day/night consensus' in commit
    assert 'queuePowerUpBreath' not in commit
    assert 'tryStartConfirmedHeadlightBreath' not in commit
    assert 'applyCurrentDoorDayNightTarget' in commit

def test_v9010_transport_baseline_is_retained():
    assert 'private var bledimSequenceByID: [UUID: UInt8]' in MONITOR
    assert 'protocolPacing=20Hz/rawBLEDIM' in MONITOR
    assert 'private func sendPowerWhenReady' in MONITOR
    assert 'private func sendColorWhenReady' in MONITOR
    assert 'private func applyRuntimeBrightnessWhenReady' in MONITOR
    assert 'Steady-state recovery begin' not in MONITOR
    assert 'BLEDIM10Hz' not in MONITOR

def test_hud_auto_brightness_uses_consensus_not_center_alone():
    assert 'Headlight consensus → Auto brightness ON' in MONITOR
    assert 'Headlight consensus → Auto brightness OFF' in MONITOR
    assert 'HUD rehydrate → consensus auto brightness' in MONITOR
    assert 'tracked Center presence remains useful for UI/status' in MONITOR

def test_newer_independent_features_are_kept():
    assert 'updateOverspeedWarning' in APP
    assert 'setAutomaticVehicleWakeAllowed' in SPOTIFY
    assert 'case enhancedOSM = "Enhanced OSM"' in SPEED
    assert 'case traceOSM = "OSM Trace"' in SPEED
    assert 'AMBIENT OVERSPEED WARNING' in VIEW
    assert 'overspeedWarningColor' in MONITOR
    assert 'overspeedWarningCooldownSeconds: TimeInterval = 60.0' in MONITOR
