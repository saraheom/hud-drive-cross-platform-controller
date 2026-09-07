from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()


def test_replay_ui_is_restored_for_parked_right_side_probe():
    assert "Recorded CarPlay lane replay" in VIEW
    assert "Send This Recorded Step" in VIEW
    assert "Auto Replay • 4 s/step" in VIEW
    assert "Right probe: Navigation" in (ROOT / "ios/HUDController/Models/HudSettings.swift").read_text()
    assert "Right probe: NaviMini" in (ROOT / "ios/HUDController/Models/HudSettings.swift").read_text()


def test_replay_still_routes_through_lane_policy_and_probe_state_machine():
    start = APP.index("func sendRecordedCarPlayLaneReplayStep")
    end = APP.index("// MARK: - Persistent stock music renderer experiment", start)
    block = APP[start:end]
    assert "navigation.navigationOn()" in block
    assert "navigation.send(step.instruction)" in block
    assert "setLaneGuidanceForCurrentManeuver" in block
    assert "HudCommands.laneGuidance(step.nativeLanes)" not in block
    assert "activateRightLaneWidgetProbeIfNeeded" in APP


def test_only_requested_diagnostic_card_returns():
    for removed in (
        "Ambient-light test build",
        "Manual navigation diagnostics",
        "Firmware-native lane guidance",
    ):
        assert removed not in VIEW


def test_replay_remains_ble_only_and_no_firmware_write():
    lowered = VIEW.lower()
    assert "no u2w adapter, adb, or firmware write is involved" in lowered
