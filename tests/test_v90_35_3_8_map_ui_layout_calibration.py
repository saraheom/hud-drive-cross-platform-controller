from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
CANVAS = (ROOT / "ios/HUDController/MapMode/HudMapModeCanvas.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()


def test_persisted_layout_offsets_and_right_side_controls():
    for token in [
        "leftOffsetX", "centerOffsetX", "rightOffsetX",
        "maneuverArrowScale", "maneuverArrowThickness",
        "laneScale", "laneArrowThickness", "laneSpacing", "laneActiveEmphasis",
        "etaScale", "resetWidgetOffsets", "resetRightComponentOffsets",
    ]:
        assert token in SETTINGS


def test_canvas_applies_visual_tuning_on_absolute_component_positions():
    for token in [
        "designerCanvasPosition(for:",
        "symbolWeight(settings.maneuverArrowThickness)",
        "settings.laneArrowThickness * 0.82",
        "settings.laneActiveEmphasis", "settings.etaScale",
    ]:
        assert token in CANVAS
    assert 'HStack(spacing: 0)' not in CANVAS


def test_ui_uses_full_canvas_designer_and_keeps_styling_controls():
    for token in [
        "Full-canvas 480×240 layout", "Navigation component styling",
        "Turn arrow boldness", "Lane arrow thickness", "Active lane emphasis",
        "setDesignerCanvasPosition", "Use lane-guidance position for ETA when lanes are unavailable",
    ]:
        assert token in UI


def test_known_good_mode6_sequence_is_preserved():
    assert "known-good join sequence: mode 6 once → credentials once → wait" in APP
    assert "IOS_KIVICCAST_STA_MODE(6) [single start]" in APP
