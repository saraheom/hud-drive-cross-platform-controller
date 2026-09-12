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


def test_canvas_applies_tuning_without_transport_changes():
    for token in [
        "settings.leftOffsetX", "settings.centerOffsetX", "settings.rightOffsetX",
        "symbolWeight(settings.maneuverArrowThickness)",
        "symbolWeight(settings.laneArrowThickness)",
        "settings.laneActiveEmphasis", "settings.etaOffsetX",
    ]:
        assert token in CANVAS


def test_ui_has_two_pixel_bounded_position_controls_and_boldness():
    for token in [
        "Physical HUD position", "Right-side maneuver / lane calibration",
        "Turn arrow boldness", "Lane boldness", "Active lane emphasis",
        "delta: -2", "delta: 2", "xRange: -20...20", "yRange: -12...12",
    ]:
        assert token in UI


def test_known_good_mode6_sequence_is_preserved():
    assert "known-good join sequence: mode 6 once → credentials once → wait" in APP
    assert "IOS_KIVICCAST_STA_MODE(6) [single start]" in APP
