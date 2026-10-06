from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAN = (ROOT / "ios/HUDController/MapMode/H264MainVideoSanitizer.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
ROOTVIEW = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()


def test_reference_frame_num_is_telemetry_while_decoder_owns_hard_recovery():
    assert "frameNumDiscontinuities" in SAN
    assert "let expected = (previous + 1) % modulus" in SAN
    assert "reference frame_num discontinuity previous=" in SAN
    assert "pendingContinuityBreakReason" in SAN
    assert "treat a single frame_num jump as telemetry" in SAN
    assert "decoder's repeated codecBadDataErr" in SAN
    assert "takeContinuityBreakReason" in SAN


def test_transport_worker_treats_single_reference_jump_as_telemetry():
    assert 'REFERENCE CONTINUITY WARNING generation=' in VIDEO
    assert 'frame forwarded, decoder remains authoritative' in VIDEO
    assert 'path remains the authoritative hard-recovery trigger' in SAN

def test_codec_bad_data_burst_escalates_after_three_not_thousands():
    assert 'consecutiveDecodeErrors >= 3' in VIDEO
    assert 'requestHardRecovery(reason: "\\(consecutiveDecodeErrors) consecutive codecBadDataErr (-8969) submissions")' in VIDEO
    assert 'outputCallbackErrors >= 3' in VIDEO
    assert 'requestHardRecovery(reason: "\\(outputCallbackErrors) codecBadDataErr (-8969) output callback failures")' in VIDEO
    assert 'sanitizer.quarantineReferenceChainUntilIDR()' in VIDEO
    assert 'decoder.hardRecoverAwaitingIDR(reason: reason)' in VIDEO
    assert 'TCP PRESERVED' in VIDEO


def test_background_transition_does_not_deliberately_kill_live_map_anymore():
    background = ROOTVIEW.split("case .background:", 1)[1].split("default:", 1)[0]
    assert 'preserving TCP/HUD cast source while VideoToolbox is lifecycle-paused' in background
    assert 'state.stopHUDU2WSTAHomeProbe()' not in background
    assert 'state.stopMainVideoPreview(reason: "app background")' not in background


def test_release_remains_navigation_safe_and_u2w_v831_is_unchanged():
    assert 'self.mainVideo.start(reason: "physical Map Mode live source (optional)")' in APP
    assert 'mainVideo.start(reason: "app-only live preview")' in APP
    assert 'v90.35.3.24.26 MainVideo client for U2W v8.37 forensic seam capture + unchanged v8.35 helper + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay' in VIDEO
    assert 'no adapter parser/cache/GOP replay' in VIDEO
    assert 'appVersion=v90.35.3.24.26' in APP
