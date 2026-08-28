from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_smooth_animation_engine_is_main_actor_isolated():
    source = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
    assert "@MainActor\n@Observable\nfinal class AmbientLightMonitor" in source
    assert "private func transitionBrightness(" in source
    assert "let timelineTick = 0.05" in source
    assert "private func sendBrightnessNormalized(" in source
    assert "protocolPacing=Lotus20Hz/BLEDIM10Hz" in source
    assert "private func startSynchronizedBreathSession()" in source


def test_temporary_ci_uses_xcode26_ambient_project():
    workflow = (ROOT / ".github/workflows/ios-ci.yml").read_text()
    assert "runs-on: macos-26" in workflow
    assert "project-ios26-ambient.yml" in workflow
    assert "runs-on: xcode-27" not in workflow


def test_future_xcode27_ci_is_manual_only():
    workflow = (ROOT / ".github/workflows/ios-ci-xcode27-future.yml").read_text()
    assert "workflow_dispatch:" in workflow
    assert "push:" not in workflow
    assert "pull_request:" not in workflow
    assert "runs-on: xcode-27" in workflow


def test_ios26_project_excludes_real_capture_source():
    spec = (ROOT / "ios/project-ios26-ambient.yml").read_text()
    assert "Navigation/ExternalNavigationCapture.swift" in spec
    assert "UI/HudNavigationView.swift" in spec
    assert "AMBIENT_IOS26_TEST" in spec
    assert "screen-capture" not in spec


def test_ios26_testflight_uses_reserved_monotonic_build_range():
    workflow = (ROOT / ".github/workflows/ios-testflight-ambient-ios26.yml").read_text()
    assert "IOS_BUILD_NUMBER=$((1000 + GITHUB_RUN_NUMBER))" in workflow
    assert "Set :CFBundleVersion $IOS_BUILD_NUMBER" in workflow
    assert 'CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER"' in workflow
    assert 'test "$VERSION" = "$IOS_BUILD_NUMBER"' in workflow
    assert 'CURRENT_PROJECT_VERSION="${{ github.run_number }}"' not in workflow


def test_future_xcode27_testflight_uses_same_monotonic_build_strategy():
    workflow = (ROOT / ".github/workflows/ios-testflight.yml").read_text()
    assert "IOS_BUILD_NUMBER=$((1000 + GITHUB_RUN_NUMBER))" in workflow
    assert "Set :CFBundleVersion $IOS_BUILD_NUMBER" in workflow
    assert 'CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER"' in workflow
    assert 'test "$VERSION" = "$IOS_BUILD_NUMBER"' in workflow
