from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
SETTINGS = (ROOT / "ios/HUDController/Models/HudSettings.swift").read_text()


def test_disproven_replay_probe_ui_is_retired_from_normal_navigation():
    assert "Recorded CarPlay lane replay" not in VIEW
    assert "Send This Recorded Step" not in VIEW
    assert "Auto Replay • 4 s/step" not in VIEW
    assert 'Picker("Lane placement"' not in VIEW
    assert "Navigation presentation" in VIEW


def test_historical_replay_backend_remains_ble_only_but_unexposed():
    start = APP.index("func sendRecordedCarPlayLaneReplayStep")
    end = APP.index("// MARK: - Persistent stock music renderer experiment", start)
    block = APP[start:end]
    assert "navigation.navigationOn()" in block
    assert "navigation.send(step.instruction)" in block
    assert "setLaneGuidanceForCurrentManeuver" in block
    assert "HudCommands.laneGuidance(step.nativeLanes)" not in block
    assert "activateRightLaneWidgetProbeIfNeeded" in APP
    for forbidden in ("adb.", "/system", "softwareUpdate"):
        assert forbidden not in block


def test_old_probe_modes_migrate_back_to_stock_center():
    assert "Right probe: Navigation" in SETTINGS
    assert "Right probe: NaviMini" in SETTINGS
    assert "lanePlacementMode = .centerNative" in SETTINGS
    assert "restoredLanePlacement != .centerNative" in SETTINGS


def test_other_legacy_diagnostic_cards_stay_hidden():
    for removed in (
        "Ambient-light test build",
        "Manual navigation diagnostics",
        "Firmware-native lane guidance",
    ):
        assert removed not in VIEW
