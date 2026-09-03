from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OBD = (ROOT / 'ios/HUDController/Vehicle/HudOBDController.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
DASH = (ROOT / 'ios/HUDController/UI/DashboardView.swift').read_text()
SETTINGS = (ROOT / 'ios/HUDController/Models/HudSettings.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()


def block(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def test_v9029_no_longer_depends_on_v9028_obd_animation_gate_workarounds():
    # v90.29 restored the previously validated OBD behavior because OBD is no
    # longer the ambient-animation gate.
    loop = block(OBD, 'private func startAutoConnectLoop', 'private func startHealthLoop')
    assert 'case 1: retryDelay = 4.0' in loop
    assert 'default: retryDelay = 30.0' in loop
    assert 'transportReacquireGraceSeconds' not in OBD
    assert 'hudAnimationGate=1' in MONITOR


def test_freeride_uses_original_profile_and_explicit_navigation_off_not_periodic_watchdog():
    assert 'center: "Simple"' in OBD
    assert '20s display watchdog' not in APP
    assert 'freerideWatchdogTask' not in APP
    restore = block(APP, 'private func restoreDashboardOperatingMode', 'func updateSpotifyVehicleWakeGate')
    assert 'HudCommands.navigationState(false)' in restore
    assert 'Restore dashboard mode → Freeride (Navigation OFF)' in restore
    assert 'if navigation.navigationActive' in restore
    assert 'HudCommands.navigationState(true)' in restore
    assert '.init(name: "Freeride", left: "Distance", center: "Simple"' in SETTINGS
    preset = block(APP, 'func applyDashboardPreset()', 'func sendNativeMusicTest')
    assert 'if p.name == "Freeride"' in preset
    assert 'obd.applyFreerideWidgets()' in preset


def test_unused_minimize_widgets_toggle_is_removed_from_dashboard_ui_only():
    assert 'Toggle("Minimize widgets"' not in DASH
    assert 'var minimizeWidgets: Bool' in SETTINGS


def test_same_displayed_speed_pending_confirmation_prevents_one_sample_mlk_blank():
    accept = block(SPEED, 'private func acceptImprovedLimit', 'private static func resolvedKmh')
    assert 'if currentSpeedLimitMph == mph {' in accept
    assert 'improvedDisplayContinuityFresh = true' in accept
    assert 'pending same-limit source confirmation' in accept
    assert 'improvedLastResolutionWarningEligible = false' in accept
    assert 'Pending same-limit confirmation — disable native warning threshold' in accept
    assert 'pending same displayed limit' in accept


def test_philly_centerline_uses_point_distance_and_keeps_pipeline_diagnostics():
    assert 'geometryType", value: "esriGeometryPoint"' in SPEED
    assert 'URLQueryItem(name: "distance", value: "650")' in SPEED
    assert 'URLQueryItem(name: "units", value: "esriSRUnit_Meter")' in SPEED
    assert 'pointRadius=650m rawFeatures=%d featuresWithSpeed=%d featuresWithGeometry=%d parsedSegments=%d' in SPEED
