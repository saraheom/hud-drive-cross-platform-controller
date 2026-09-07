from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_active_probe_reconfigures_when_candidate_changes():
    app = (ROOT / "ios/HUDController/App/AppState.swift").read_text(encoding="utf-8")
    start = app.index("private func activateRightLaneWidgetProbeIfNeeded")
    end = app.index("private func restoreNormalNavigationAfterLaneProbeIfNeeded", start)
    probe = app[start:end]
    assert "laneRightSideProbeWidget" in app
    assert "laneRightSideProbeWidget != rightWidget" in probe
    assert "if laneRightSideProbeActive && !reconfiguring { return }" in probe
    assert "laneRightSideProbeWidget = rightWidget" in probe
    assert '"\\(reconfiguring ? "reconfigure" : "activate") right=\\(rightWidget)' in probe
    assert 'label: "Lane right-side probe → \\(rightWidget)"' in probe


def test_probe_widget_identity_clears_on_restore_disconnect_and_policy_clear():
    app = (ROOT / "ios/HUDController/App/AppState.swift").read_text(encoding="utf-8")
    assert app.count("laneRightSideProbeWidget = nil") >= 3
