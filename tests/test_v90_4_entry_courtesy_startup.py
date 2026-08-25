from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def monitor_source():
    return (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_engine_start_timestamp_anchors_hidden_courtesy_settle_window():
    src = monitor_source()
    assert "enginePowerBecamePresentAt" in src
    assert "enginePowerBecamePresentAt = Date()" in src
    assert "startupClassificationSeconds - elapsedSinceEngineOn" in src
    assert "no light brightness is changed during the settle window" in src


def test_startup_night_detector_rejects_pre_engine_advertisements():
    src = monitor_source()
    block = src.split("private func startupHeadlightPowerPresent", 1)[1].split("private func doorTargetBrightness", 1)[0]
    assert "seen >= engineOnAt" in block
    assert "peripheralsByID[id]?.state == .connected" in block
    assert "now.timeIntervalSince(seen) <= 2.0" in block
    assert "isLogicallyPowered" not in block


def test_finish_startup_only_classifies_door_day_night():
    src = monitor_source()
    block = src.split("private func finishVehicleStartupClassification()", 1)[1].split("private func applyCurrentDoorDayNightTarget", 1)[0]
    assert "startupHeadlightPowerPresent()" in block
    assert "applyCurrentDoorDayNightTarget" in block
    assert "Vehicle startup pulse" not in block
    assert "fadeIn" not in block


def test_ui_keeps_courtesy_logic_concise_and_hides_old_tuning_controls():
    view = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
    assert "Pre-engine courtesy headlights are ignored by a short internal settle window" in view
    assert "Post-engine headlight settle window" not in view
    assert "Headlight join fade" not in view
    assert "Shutdown fade" not in view
