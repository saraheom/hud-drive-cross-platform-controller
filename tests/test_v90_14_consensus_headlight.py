from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
SPOTIFY = (ROOT / 'ios/HUDController/Media/SpotifyMediaController.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
VIEW = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()

def test_two_controller_consensus_remains_stable_diagnostic_crosscheck():
    assert 'private enum HeadlightConsensusObservation' in MONITOR
    assert 'case bothOn' in MONITOR and 'case bothOff' in MONITOR and 'case mixed' in MONITOR
    assert 'headlightConsensusStabilitySeconds: TimeInterval = 0.75' in MONITOR
    assert 'Dashboard+Center diagnostic consensus' in MONITOR
    assert 'Center/BLEDOM remains authoritative for fast day/night' in MONITOR


def test_center_day_night_owner_does_not_own_animation():
    commit = MONITOR.split('private func commitConfirmedHeadlightPower', 1)[1].split('private func noteHeadlightPowerSeen', 1)[0]
    assert 'Fast Center day/night' in commit
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

def test_hud_auto_brightness_uses_fast_center_presence():
    assert 'Center presence → Auto brightness ON' in MONITOR
    assert 'Center absence → Auto brightness OFF' in MONITOR
    assert 'HUD rehydrate → Center-driven auto brightness' in MONITOR
    assert 'Center-driven watchdog reasserted HUD auto brightness' in MONITOR


def test_newer_independent_features_are_kept():
    assert 'updateOverspeedWarning' in APP
    assert 'setAutomaticVehicleWakeAllowed' in SPOTIFY
    assert 'case traceOSM = "OSM Trace"' in SPEED
    assert 'case improvedTracePhilly = "Improved + Philly GIS"' in SPEED
    assert 'AMBIENT OVERSPEED WARNING' in VIEW
    assert 'overspeedWarningColor' in MONITOR
    assert 'overspeedWarningCooldownSeconds: TimeInterval = 60.0' in MONITOR
