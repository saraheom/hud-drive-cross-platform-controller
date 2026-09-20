from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()

def test_stale_lane_renderer_reset_sequence_is_present():
    assert "schedulePhysicalLaneRendererResetAfterClear" in APP
    assert "self.obd.applyNavigationWidgets()" in APP
    assert "self.navigation.sendCurrent(owner: self.navigation.feedOwner)" in APP
    assert 'label: "Lane renderer reset → final clear"' in APP
    assert '"HUD LANE RESET"' in APP

def test_stale_lane_renderer_reset_is_generation_guarded():
    assert "private var laneRendererResetTask: Task<Void, Never>?" in APP
    assert "self.lanePresentationGeneration == generation" in APP
    assert "self.activeLaneGuidance.isEmpty" in APP
    assert "let hadLanePayload = !activeLaneGuidance.isEmpty" in APP
    assert "guard hadLanePayload, navigation.navigationActive else { return }" in APP

def test_v9035242_dual_wire_handshake_is_preserved():
    assert "U2WH2642" in VIDEO
    assert "U2WH2643" in VIDEO
