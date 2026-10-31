"""Production UI and bounded recovery checks for v24.48.

All speed-limit and HUD-video controls remain governed by CarPlay road identity,
real OSM data and read-only adapter recovery; this test guards the requested UI
cleanup and ensures the driving path did not inherit the old FPS preference.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
AMBIENT = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
SETTINGS = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()


def test_compact_ui_keeps_daily_controls_and_removes_old_test_panels():
    for name in ["Automatic Map Mode", "Save adapter Wi-Fi & retry Map Mode", "Map Mode image customization", "Prevent Auto-Lock during Map Mode"]:
        assert name in UI
    for removed in ["Test stock HUD message (parked)", "Collect Live Map Diagnostic ZIP (parked)", "Map Mode FPS", "Keep decoder + BG task", "Decoder:"]:
        assert removed not in UI
    assert "BLEDIM PRODUCTION ANIMATION" not in AMBIENT
    assert "Already-On Minimal" not in AMBIENT
    assert "previewEnabledBLEDIMBreathNow" in MONITOR  # underlying animation behavior preserved
    assert "collectLiveMapDiagnosticBundle()" in APP  # underlying diagnostic method preserved


def test_fps_is_fastest_field_validated_rate_even_with_stale_saved_preference():
    assert "supportedHUDFrameRates.max() ?? 15" in SETTINGS
    assert APP.count("HudMapModeSettings.supportedHUDFrameRates.max() ?? 15") >= 3
    assert '"HUD.MapMode.hudFrameRate"' in SETTINGS  # backward compatible persistence


def test_hud_viewer_status_timeout_is_not_indistinguishable_from_disconnect():
    assert 'let statusUnavailable = relay.sessionID == "—"' in APP
    assert "if inconclusiveStatusFailures < 5 { continue }" in APP
    assert "consecutiveViewerFailures >= 3" in APP
    assert '"AUTOMATIC_REJOIN_RETRY after transient failure' in APP
    assert "hudU2WDisplayRecoveryCount < 2" in APP
    assert "self.hudU2WCurrentSessionWasReady" in APP


def test_mid_drive_idr_recovery_bounded_and_source_not_manipulated():
    assert "self.midDriveRecoveryAttemptCount < 2" in VIDEO
    assert '"WAITING_LIVE_IDR" && self.midDriveRecoveryAttemptCount > 0' in VIDEO
    assert "self.midDriveRecoveryAttemptCount = 0" in VIDEO
    assert "restartWorkerWithReadOnlyBootstrap" in VIDEO
    assert "no adapter reset or CarPlay intervention" in VIDEO


def test_initial_untagged_same_road_evidence_is_limited_and_warning_off():
    start = SPEED.index("private func connectedCurrentNavLimit")
    end = SPEED.index("private func bestCurrentNavSpeedLimit", start)
    function = SPEED[start:end]
    assert "minDistance <= 850" in function
    assert "for _ in 0..<30" in function
    assert "Self.endpointDistance(node, candidate) <= 20" in function
    assert "Self.isIncompatibleHighwayClass" in function
    assert "guard posted.count == 1" in function
    assert "currentNavDisplayHold = true // connected-road value is display only" in SPEED
    assert "if currentNavObservedStreet != identity" in SPEED
