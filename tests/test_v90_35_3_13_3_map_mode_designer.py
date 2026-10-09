from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
CANVAS = (ROOT / "ios/HUDController/MapMode/HudMapModeCanvas.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()


def test_three_preset_slots_and_migration_of_existing_layout():
    assert 'for index in 0..<3' in SETTINGS
    assert 'Self.importedBaselineKey' in SETTINGS
    assert 'Preset 1 *before* loading or applying any preset state' in SETTINGS
    assert 'store.set(data, forKey: Self.presetKey(index))' in SETTINGS
    assert 'func selectPreset(_ index: Int)' in SETTINGS
    assert 'func restoreImportedLayout()' in SETTINGS


def test_preset_autosaves_complete_map_mode_state():
    assert 'private struct HudMapModePresetSnapshot: Codable' in SETTINGS
    assert 'presetValueDidChange()' in SETTINGS
    for token in [
        'sourceMapZoom = settings.sourceMapZoom',
        'speedLimitFontScale = settings.speedLimitFontScale',
        'showLaneGuidance = settings.showLaneGuidance',
        'mapAppearanceRaw = settings.mapAppearance.rawValue',
        'designerTimeLeftOffsetY = settings.designerTimeLeftOffsetY',
    ]:
        assert token in SETTINGS


def test_designer_supports_all_requested_components():
    for case in [
        'case speed', 'case speedLimit', 'case map', 'case turningStreet',
        'case maneuver', 'case distance', 'case lanes', 'case eta', 'case timeLeft'
    ]:
        assert case in SETTINGS
    assert 'ForEach(designerComponents)' in UI
    assert 'DragGesture(minimumDistance: 1)' in UI
    assert 'setDesignerCanvasPosition(selectedDesignerComponent' in UI
    assert 'snapDesignerPixel' in UI


def test_designer_uses_one_true_480x240_canvas_while_migrating_legacy_calibration():
    assert 'designerCanvasPosition(for component:' in SETTINGS
    assert 'setDesignerCanvasPosition' in SETTINGS
    assert 'defaultCanvasPosition' in SETTINGS
    assert 'frame(width: 480, height: 240)' in CANVAS
    assert '.position(canvasPoint(.map))' in CANVAS
    assert '.position(canvasPoint(.maneuver))' in CANVAS
    assert '.position(canvasPoint(.lanes))' in CANVAS
    assert '.position(canvasPoint(.eta))' in CANVAS
    # Legacy offsets remain only as migration/default anchors, not parent layout boundaries.
    assert 'return (centerOffsetX, centerOffsetY)' in SETTINGS
    assert 'return (rightOffsetX + maneuverOffsetX, rightOffsetY + maneuverOffsetY)' in SETTINGS
    assert 'return (rightOffsetX + laneOffsetX, rightOffsetY + laneOffsetY)' in SETTINGS
    assert 'case .map: return (designerMapOffsetX, designerMapOffsetY)' in SETTINGS
    assert 'settings.speedScale' in CANVAS


def test_quick_switch_is_outside_customization_disclosure():
    assert UI.index('presetQuickSwitch') < UI.index('mapModeRelayControls')
    assert 'Picker(\n                "Map design preset"' in UI
    assert 'auto-saved' in UI
