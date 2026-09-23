from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
AMBIENT = (ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
ROOTVIEW = (ROOT/'ios/HUDController/UI/RootView.swift').read_text()


def test_invalid_videotoolbox_session_is_fatal_and_tcp_is_preserved():
    assert 'private static let invalidSessionStatus: OSStatus = -12903' in VIDEO
    assert 'FATAL VideoToolbox invalid session' in VIDEO
    assert 'requestHardRecovery(reason:' in VIDEO
    assert 'Decoder hard recovery #' in VIDEO
    assert 'waiting for validated IDR' in VIDEO
    assert 'relay-aware live-IDR wait' in VIDEO and 'TCP PRESERVED' in VIDEO


def test_silent_decoder_output_stall_recovers_even_when_decode_call_returns_noerr():
    assert 'fresh H.264 but no decoded frame for' in VIDEO
    assert 'decoderStaleFrameInterval: TimeInterval = 3.0' in VIDEO
    assert 'VideoToolbox output callback failure' in VIDEO
    assert 'soft-flushing delayed VideoToolbox frames before hard recovery' in VIDEO
    assert 'outputErr=' in VIDEO and 'outputStatus=' in VIDEO
    assert 'kVTDecompressionPropertyKey_RealTime' in VIDEO


def test_preflight_requires_sustained_continuity_not_two_frames():
    assert 'preflightRequiredContinuity: TimeInterval = 20.0' in VIDEO
    assert 'frameCount >= 30' in VIDEO
    assert 'LIVE • 20s continuity verified' in VIDEO
    assert 'PASS 20s continuous decode' in VIDEO


def test_scene_lifecycle_is_connected_to_mainvideo_recovery():
    assert 'state.mainVideo.applicationDidEnterBackground()' in ROOTVIEW
    assert 'state.mainVideo.applicationDidBecomeActive()' in ROOTVIEW
    assert 'decoder preserved across lifecycle transition' in VIDEO


def test_native_lane_layer_is_cleared_after_maneuver_without_owned_lanes():
    assert 'Lane policy → post-maneuver clear' in APP
    assert 'Lane policy → post-maneuver settle clear' in APP
    assert 'lanePresentationGeneration' in APP
    assert 'Task.sleep(for: .milliseconds(150))' in APP
    assert 'postManeuverLaneClearTask?.cancel()' in APP


def test_live_preview_never_invents_default_three_lanes():
    live_preview = UI.split('snapshot: state.mapModePreviewSnapshot', 1)[1].split(')', 1)[0]
    assert 'previewLanePlaceholder: false' in live_preview
    assert 'snapshot: .customizationDemo' in UI


def test_center_only_guard_commits_day_without_waiting_for_dashboard():
    assert 'centerDayGuardSeconds: TimeInterval = 1.0' in AMBIENT
    assert 'Center-only DAY guard armed' in AMBIENT
    assert 'Dashboard not required' in AMBIENT
    assert 'Dashboard+Center BOTH-OFF stable; fast corroborated DAY commit' not in AMBIENT


def test_map_mode_sta_join_has_one_bounded_automatic_recovery():
    assert 'AUTO JOIN RECOVERY begin mode4→mode6→credentials' in APP
    assert 'hudU2WAutomaticJoinRecoveryCount' in APP
    assert 'hudU2WAutomaticJoinRecoveryCount == 0' in APP
    assert 'HUD has Wi-Fi IP — verifying current display session…' in APP
    assert '(status == 4 || status == 6)' in APP
    assert 'for checkpoint in 1...2' in APP
