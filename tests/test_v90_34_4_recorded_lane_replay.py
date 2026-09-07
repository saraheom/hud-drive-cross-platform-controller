from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_recorded_replay_has_both_physical_sources_and_real_record_ids():
    src = text("ios/HUDController/Navigation/RecordedCarPlayLaneReplay.swift")
    assert 'case appleMaps' in src
    assert 'case googleMaps' in src
    for record in (170, 171, 172, 173, 174, 175, 278, 115, 116, 117, 118, 132, 133, 134):
        assert f'record: {record}' in src


def test_recorded_replay_normalizes_all_stock_lane_shapes():
    src = text("ios/HUDController/Navigation/RecordedCarPlayLaneReplay.swift")
    assert "if hasLeft && hasStraight { return .straightLeft }" in src
    assert "if hasRight && hasStraight { return .straightRight }" in src
    assert "if hasLeft { return .left }" in src
    assert "if hasRight { return .right }" in src
    assert "return .straight" in src


def test_replay_ui_is_parked_manual_and_not_live_route_integration():
    nav = text("ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift")
    app = text("ios/HUDController/App/AppState.swift")
    live = text("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")

    assert "Recorded CarPlay lane replay" not in nav
    assert "Send This Recorded Step" not in nav
    assert "◀ Previous" not in nav
    assert "Next ▶" not in nav
    assert "Auto Replay • 4 s/step" not in nav
    assert "Raw CarPlay lane angles" not in nav
    assert "Native HUD signed values" not in nav
    # The captured fixtures and sender remain in source for regression/engineering use,
    # but the obsolete parked replay controls are no longer part of the user UI.
    assert "sendRecordedCarPlayLaneReplayStep" in app
    # v90.34.4 stays diagnostic-first: no 0x5204 lane injection into live adapter polling yet.
    assert "HudCommands.laneGuidance" not in live


def test_no_firmware_write_commands_added_to_replay_path():
    replay = text("ios/HUDController/Navigation/RecordedCarPlayLaneReplay.swift").lower()
    app = text("ios/HUDController/App/AppState.swift")
    start = app.index("func sendRecordedCarPlayLaneReplayStep")
    end = app.index("func sendNativeMusicMiniTest", start)
    replay += "\n" + app[start:end].lower()
    for forbidden in ("adb push", "adb root", "remount", "bootanimation.zip", "system/media"):
        assert forbidden not in replay
