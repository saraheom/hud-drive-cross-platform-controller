from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()


def test_version_and_adapter_pairing_stay_v837():
    assert "v90.35.3.24.28 MainVideo client for U2W v8.37" in VIDEO
    assert 'appVersion=v90.35.3.24.28' in APP


def test_codec_bad_data_is_staged_before_hard_reset():
    assert "CODEC_BAD_DATA_GRACE_ARMED" in VIDEO
    assert "CODEC_BAD_DATA_GRACE_RECOVERED" in VIDEO
    assert "CODEC_BAD_DATA_GRACE_EXHAUSTED" in VIDEO
    assert "codecBadDataGraceAccessUnitBudget = 24" in VIDEO
    assert "codecBadDataGraceTimeBudget: TimeInterval = 2.0" in VIDEO
    assert 'requestHardRecovery(reason: "sustained codecBadDataErr (-8969) after bounded grace")' in VIDEO
    assert 'requestHardRecovery(reason: "\\(outputCallbackErrors) codecBadDataErr (-8969) output callback failures")' not in VIDEO
    assert 'requestHardRecovery(reason: "\\(consecutiveDecodeErrors) consecutive codecBadDataErr (-8969) submissions")' not in VIDEO


def test_successful_image_cancels_bad_data_grace():
    assert "successful image output preserved the existing reference chain" in VIDEO
    assert "clearCodecBadDataGrace()" in VIDEO
    assert "rebuildAtNextIDR = true" in VIDEO


def test_reserved_failure_window_not_spent_on_lifecycle_invalid_session():
    block = VIDEO.split("let isFirstFailureSignal =", 1)[1].split("if isFirstFailureSignal", 1)[0]
    assert "codecBadDataErr" in block
    assert 'message.contains("-8969")' in block
    assert 'message.contains("-12903")' not in block
    assert 'REFERENCE CONTINUITY WARNING' not in block


def test_current_hud_viewer_requires_live_socket_not_historical_latches():
    assert "sessionScoped ? (established && clientSeen && liveFrameSent) : established" in APP
    assert "hudU2WReadySessionID" in APP
    assert "current HUD MJPEG viewer no longer established/session-ready" in APP
    assert "consecutiveViewerFailures >= 2" in APP
    assert "let relay = await self.u2wHUDRelayStatus()" in APP
