from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
MODEL = (ROOT / 'ios/HUDController/Vehicle/AmbientLightModels.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
SPOTIFY = (ROOT / 'ios/HUDController/Media/SpotifyMediaController.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
VEHICLE = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()


def test_configurable_overspeed_warning_is_retained():
    assert 'case door = "Door"' in MODEL
    assert 'case dashboard = "Dashboard"' in MODEL
    assert 'let threshold = speedLimitMph + offset' in MONITOR
    assert 'let above = gpsSpeedMph > threshold' in MONITOR
    assert 'let crossedUp = above && !overspeedAboveThreshold' in MONITOR
    assert 'AmbientRGB(red: 255, green: 0, blue: 0)' in MONITOR
    assert 'overspeedWarningCooldownSeconds: TimeInterval = 60.0' in MONITOR
    assert 'max(0.0, min(5.0, overspeedWarningPulseDurationSeconds))' in MONITOR
    assert 'sendPowerWhenReady(id, on: false' not in MONITOR.split('private func triggerOverspeedWarning',1)[1].split('// MARK: - Connection management',1)[0]


def test_overspeed_ui_and_fresh_limit_wiring_are_retained():
    assert 'AMBIENT OVERSPEED WARNING' in VEHICLE
    assert 'Warning color' in VEHICLE
    assert 'in: 0.0...5.0' in VEHICLE
    assert 'Repeat cooldown' in VEHICLE
    assert 'speedLimitAvailableForWarning' in SPEED
    assert 'onSpeedStateChanged' in SPEED
    assert 'ambientLight?.updateOverspeedWarning' in APP


def test_spotify_vehicle_gate_is_retained():
    assert 'automaticVehicleWakeAllowed' in SPOTIFY
    assert 'guard automaticVehicleWakeAllowed else' in SPOTIFY
    assert 'let nowPlaying: CarPlayNowPlayingClient' in APP
    assert 'updateSpotifyVehicleWakeGate' not in APP
