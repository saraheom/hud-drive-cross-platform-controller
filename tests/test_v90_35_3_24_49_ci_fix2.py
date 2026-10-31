"""Regression for GitHub iOS CI run 111567414187 (7 stale XCTest UI assertions).

The app compiled. Legacy source-text XCTest assertions, left over from the old
Map Mode and Ambient UI, caused seven failures despite functioning controls.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "ios" / "HUDControllerTests"
MAP_UI = ROOT / "ios" / "HUDController" / "UI" / "NavigationHUDPreviewCard.swift"
AMBIENT_UI = ROOT / "ios" / "HUDController" / "UI" / "AmbientLightingView.swift"


def test_retired_ui_labels_are_not_required_by_swift_xctest():
    # The tests should reflect the simplified production UI, not reintroduce
    # text and buttons intentionally retired in v24.48.
    for name in (
        "V9021BLEDIMAnimationTestLabTests.swift",
        "V903522LiveIDRLaneAmbientTests.swift",
        "V90352410IncrementalSourceAcquireTests.swift",
        "V90352429StartupBootstrapFullCanvasTests.swift",
        "V90352431ResourceSafeBackgroundProbeTests.swift",
        "V903538MapUILayoutCalibrationTests.swift",
    ):
        source = (TESTS / name).read_text()
        assert 'XCTAssertTrue(ui.contains("Detailed MainVideo' not in source
        assert 'XCTAssertTrue(ui.contains("Background continuity"))' not in source
        assert 'XCTAssertTrue(ui.contains("Full-canvas 480×240 layout"))' not in source
        assert 'XCTAssertTrue(view.contains("Preview BLEDIM Only"))' not in source
        assert 'XCTAssertTrue(ui.contains(#"Decoder: ' not in source


def test_daily_controls_still_exist_without_removed_experiment_buttons():
    ui = MAP_UI.read_text()
    ambient = AMBIENT_UI.read_text()
    for text in ('Map stream', 'Automatic Map Mode', 'Prevent Auto-Lock during Map Mode',
                 'Map Mode layout designer', 'Music Overlay'):
        assert text in ui
    assert 'Preview Enabled Lights' in ambient
    assert 'Preview BLEDIM Only' not in ambient
    assert 'BLEDIM PRODUCTION ANIMATION' not in ambient


def test_early_ci_static_source_contract_preflight_succeeds():
    checker = ROOT / 'scripts' / 'validate_swift_test_source_assertions.py'
    workflow = (ROOT / '.github' / 'workflows' / 'ios-ci.yml').read_text()
    assert 'python3 scripts/validate_swift_test_source_assertions.py' in workflow
    result = subprocess.run([sys.executable, str(checker)], capture_output=True, text=True, timeout=25)
    assert result.returncode == 0, result.stdout + result.stderr
    assert '0 mismatches' in result.stdout
