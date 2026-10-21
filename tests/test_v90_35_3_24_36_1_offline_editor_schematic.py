"""v24.36.1 restores the dummy map only inside offline layout customization."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANVAS = (ROOT/'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
RENDER = (ROOT/'ios/HUDController/MapMode/HudMapModeFrameRenderer.swift').read_text()


def test_schematic_uses_editor_only_opt_in():
    assert 'var showsCustomizationSampleMap = false' in CANVAS
    branch = CANVAS.split('private var mapBlock: some View {', 1)[1].split('private var streetBlock:', 1)[0]
    assert 'if let sourceMapImage {' in branch
    assert 'else if showsCustomizationSampleMap {' in branch
    assert 'HudMapModeSchematic(' in branch
    assert 'Color.black' in branch.split('HudMapModeSchematic(',1)[1]


def test_both_offline_previews_explicitly_enable_sample_map():
    assert UI.count('snapshot: .customizationDemo') == 2
    assert UI.count('showsCustomizationSampleMap: true') == 2
    assert UI.index('snapshot: state.mapModePreviewSnapshot') < UI.index('showsCustomizationSampleMap: true')
    header=UI.split('private var header:', 1)[0]
    assert 'showsCustomizationSampleMap: true' not in header


def test_real_jpeg_hud_output_does_not_enable_sample_map():
    assert 'showsCustomizationSampleMap: true' not in RENDER
    assert 'sourceMapImage: sourceMapImage,' in RENDER
    assert 'showsCustomizationSampleMap' not in (ROOT/'ios/HUDController/App/AppState.swift').read_text()


def test_presets_and_reset_undo_logic_unmodified_by_editor_fix():
    settings=(ROOT/'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
    assert 'Undo' in UI or 'undo' in UI
    assert 'activePresetIndex' in settings
    assert '.confirmationDialog(' in UI
