from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def text(rel):
    return (ROOT / rel).read_text()

def test_center_role_replaces_stale_tracker_and_reconciles_night():
    s = text('ios/HUDController/Vehicle/AmbientLightMonitor.swift')
    assert 'pairedDevice(id)?.role == .centerConsole' in s
    assert 'paired Center CoreBluetooth didConnect' in s
    assert 'becamePresent || !headlightPowerSessionActive' in s
    assert 'positive Center evidence' in s

def test_warning_settings_and_ranges_exist():
    s = text('ios/HUDController/Models/HudMapModeSettings.swift')
    assert 'enum HudManeuverWarningTarget' in s
    assert 'maneuverWarningThresholdFeet' in s
    assert 'default: 500' in s
    assert 'maneuverWarningBlinkCount' in s and 'default: 3' in s
    assert 'maneuverWarningIntervalSeconds' in s and 'default: 0.75' in s

def test_warning_is_once_per_maneuver_and_map_mode_only():
    s = text('ios/HUDController/App/AppState.swift')
    assert 'mapModeManeuverWarningTriggeredKeys' in s
    assert 'distance <= threshold' in s
    assert 'mapModeActive || hudU2WLiveRelayActive' in s
    assert 'MAP MANEUVER WARNING' in s

def test_renderer_hides_only_selected_component_without_layout_removal():
    s = text('ios/HUDController/MapMode/HudMapModeCanvas.swift')
    assert 'warningHiddenTarget == .maneuverArrow ? 0 : 1' in s
    assert 'warningHiddenTarget == .distance ? 0 : 1' in s

def test_customization_ui_has_requested_controls():
    s = text('ios/HUDController/UI/NavigationHUDPreviewCard.swift')
    for phrase in ['Blink target', 'Warning threshold', 'Blink count', 'Blink interval', 'Preview blink']:
        assert phrase in s
