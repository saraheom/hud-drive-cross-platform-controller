from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
VIEW = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()


def test_six_historical_bledim_strategies_remain_decodable_but_minimal_is_default():
    for case in [
        "v90172Baseline", "baselineHold", "brightnessOnlyFinish",
        "noTerminalCommit", "alreadyOnMinimal", "v9018NoFlash",
    ]:
        assert f"case {case}" in MODEL
    assert ") ?? .alreadyOnMinimal" in MONITOR
    assert "? .alreadyOnMinimal" in MONITOR


def test_v9022_removes_strategy_picker_and_preview_uses_production_minimal():
    assert "previewEnabledBLEDIMBreathNow" in MONITOR
    assert "bledimStrategyOverride: override" not in MONITOR
    assert "BLEDIM ANIMATION TEST LAB" not in VIEW
    assert "BLEDIM PRODUCTION ANIMATION" in VIEW
    assert "Already-On Minimal" in VIEW
    assert "Preview BLEDIM Only" in VIEW
    assert "Apply selected strategy to automatic BLEDIM power-on" not in VIEW


def test_diagnostic_methods_isolate_start_and_end_flash_hypotheses():
    assert "hold 0.75 s" in MODEL
    assert "Preferred only" in MODEL
    assert "no extra terminal command" in MODEL
    assert "No preparation write" in MODEL
    assert "RGB → Preferred → Power ON → Preferred" in MODEL
    assert "BLEDIM diagnostic hold begin 0.75s" in MONITOR
    assert "BLEDIM final=no-extra-write" in MONITOR
