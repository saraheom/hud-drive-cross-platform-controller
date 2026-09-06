from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_v70_imperial_regression_tracks_generalized_instruction_sender():
    test = (ROOT / "ios/HUDControllerTests/V70ImperialUnitsAndUS1Tests.swift").read_text()
    nav = (ROOT / "ios/HUDController/Navigation/HudNavigationController.swift").read_text()
    assert 'HudCommands.maneuver(instruction)' in test
    assert 'HudCommands.maneuver(current)' not in test
    unit = nav.index('HudCommands.imperialUnits()')
    maneuver = nav.index('HudCommands.maneuver(instruction)')
    assert unit < maneuver
