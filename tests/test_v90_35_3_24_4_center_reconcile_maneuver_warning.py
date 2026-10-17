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
    assert 'maneuverWarningThresholdFeet' in s
    assert 'default: 500' in s

def test_turn_warning_is_continuous_distance_color_and_map_mode_rendered():
    s = text('ios/HUDController/MapMode/HudMapModeCanvas.swift')
    assert 'turnDistanceWarningActive' in s
    assert 'snapshot.distanceToManeuverMeters' in s
    assert 'maneuverWarningThresholdFeet' in s
    assert '.foregroundStyle(turnDistanceWarningActive ? warningTextColor : .white)' in s


def test_renderer_no_longer_blinks_or_hides_turn_components():
    s = text('ios/HUDController/MapMode/HudMapModeCanvas.swift')
    assert 'warningHiddenTarget == .maneuverArrow' not in s
    assert 'warningHiddenTarget == .distance' not in s


def test_compact_warning_ui_has_turn_threshold_and_shared_color():
    s = text('ios/HUDController/UI/NavigationHUDPreviewCard.swift')
    for phrase in ['Map Mode Warnings', 'Turn distance warning', 'Warning below', 'Warning text color']:
        assert phrase in s
    assert 'Preview blink' not in s
