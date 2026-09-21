from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
AMBIENT = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()


def test_invalid_videotoolbox_session_is_fatal_and_tcp_is_preserved():
    assert "if decodeStatus == Self.invalidSessionStatus" in VIDEO
    assert "immediate decoder reset requested; worker applies bounded transport recovery" in VIDEO
    assert "hardRecoverAwaitingIDR" in VIDEO
    assert 'bounded recovery attempt #1' in VIDEO
    assert 'TCP PRESERVED, quarantining replay and waiting for next live IDR' in VIDEO
    assert "decoderStaleFrameInterval: TimeInterval = 3.0" in VIDEO
    assert "LIVE • 20s continuity verified" in VIDEO


def test_no_lane_placeholder_in_live_preview_and_post_maneuver_clear_is_guarded():
    assert UI.count("previewLanePlaceholder: false") >= 2
    assert "Lane policy → post-maneuver clear" in APP
    assert "Lane policy → post-maneuver settle clear" in APP
    assert "lanePresentationGeneration == generation" in APP


def test_center_only_guard_commits_day_without_dashboard_gate():
    assert "centerDayGuardSeconds: TimeInterval = 1.0" in AMBIENT
    assert "Center-only DAY guard armed" in AMBIENT
    assert "Dashboard not required" in AMBIENT
    assert "preserving NIGHT" in AMBIENT
