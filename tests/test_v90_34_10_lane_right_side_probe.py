from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_lane_placement_modes_are_persisted_and_safe_by_default():
    settings = read("ios/HUDController/Models/HudSettings.swift")
    assert "enum HudLanePlacementMode" in settings
    assert "case centerNative" in settings
    assert "case rightNavigationProbe" in settings
    assert "case rightNaviMiniProbe" in settings
    assert 'HUD.Settings.lanePlacementMode' in settings
    assert 'HudLanePlacementMode.centerNative.rawValue' in settings
    assert 'lanePlacementMode = .centerNative' in settings


def test_right_side_probe_uses_only_stock_widget_packets_and_restores_dashboard():
    app = read("ios/HUDController/App/AppState.swift")
    start = app.index("private func activateRightLaneWidgetProbeIfNeeded")
    end = app.index("private func restoreNormalNavigationAfterLaneProbeIfNeeded")
    probe = app[start:end]
    assert "HudCommands.dashboard" in probe
    assert 'center: "Navigation"' in probe
    assert "right: rightWidget" in probe
    assert "navigation.sendCurrent" in probe
    assert "/system" not in probe
    assert "adb." not in probe.lower()
    assert "maintenance" not in probe.lower()

    restore_start = end
    restore_end = app.index("private func sendActiveLaneGuidance", restore_start)
    restore = app[restore_start:restore_end]
    assert "obd.applyNavigationWidgets()" in restore
    assert "navigation.sendCurrent" in restore


def test_disproven_lane_probe_is_no_longer_exposed_in_navigation_ui():
    view = read("ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift")
    assert 'Picker("Lane placement"' not in view
    assert "Right-side probe keeps the normal center Navigation renderer" not in view
    assert "Recorded CarPlay lane replay" not in view
    assert "Navigation presentation" in view
    for removed in (
        "Ambient-light test build",
        "Manual navigation diagnostics",
        "Firmware-native lane guidance",
    ):
        assert removed not in view


def test_background_research_records_hardcoded_stock_constraint_without_patching_launcher():
    doc = read("docs/V90_34_10_LANE_RIGHT_SIDE_PROBE_BACKGROUND_RESEARCH.md")
    assert 'Color.parseColor("#252525")' in doc
    assert "Canvas.drawRoundRect" in doc
    assert "No ADB connection, APK replacement, `/system` write" in doc
