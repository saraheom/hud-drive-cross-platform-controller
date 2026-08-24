from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def monitor_source():
    return (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_engine_start_timestamp_anchors_startup_settle_window():
    src = monitor_source()
    assert "enginePowerBecamePresentAt" in src
    assert "enginePowerBecamePresentAt = Date()" in src
    assert "startupClassificationSeconds - elapsedSinceEngineOn" in src
    assert "Pre-engine Dashboard/Console presence is ignored" in src


def test_startup_night_detector_rejects_pre_engine_advertisements():
    src = monitor_source()
    block = src.split("private func startupHeadlightPowerPresent", 1)[1].split("private func doorTargetBrightness", 1)[0]
    assert "seen >= engineOnAt" in block
    assert "peripheralsByID[id]?.state == .connected" in block
    assert "now.timeIntervalSince(seen) <= 2.0" in block
    assert "isLogicallyPowered" not in block


def test_finish_startup_uses_strict_post_engine_detector_not_steady_hysteresis():
    src = monitor_source()
    block = src.split("private func finishVehicleStartupClassification()", 1)[1].split("private func prepareForVehicleStartup", 1)[0]
    assert "let nightStart = startupHeadlightPowerPresent()" in block
    assert "headlightPowerPresent()" not in block
    assert "courtesy headlights turned off after engine start" in block
    assert "headlight-fed lights remained powered after engine start" in block


def test_ui_explains_entry_courtesy_headlight_behavior():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert 'title: "Post-engine headlight settle window"' in view
    assert "courtesy headlights" in view
    assert "pre-engine state is ignored" in view
    assert "if either headlight-fed light remains powered it classifies Night" in view
