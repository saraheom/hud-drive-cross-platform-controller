from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
SPOTIFY = (ROOT / "ios/HUDController/Media/SpotifyMediaController.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
VEHICLE = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
MEDIA = (ROOT / "ios/HUDController/UI/MediaView.swift").read_text()


def test_headlight_state_uses_two_light_consensus_instead_of_center_authority():
    assert "private enum HeadlightConsensusObservation" in MONITOR
    assert "both Center + Dashboard stable ON" in MONITOR
    assert "both Center + Dashboard stable OFF" in MONITOR
    assert "setAuthoritativeHeadlightPower" not in MONITOR
    assert "Headlight consensus → Auto brightness ON" in MONITOR
    assert "Headlight consensus → Auto brightness OFF" in MONITOR


def test_headlight_breath_waits_for_both_gatt_ready_and_epoch_is_generation_safe():
    assert "headlightStateGeneration" in MONITOR
    assert "private func tryStartConfirmedHeadlightBreath" in MONITOR
    assert "isControllable(dashboardID)" in MONITOR
    assert "isControllable(centerID)" in MONITOR
    assert "headlightAnimatedEpochByID" in MONITOR


def test_spotify_automatically_wakes_after_repeated_failures_without_clearing_token():
    assert "private func attemptAutomaticSpotifyWake" in SPOTIFY
    assert "consecutiveConnectionFailures >= 2" in SPOTIFY
    auto = SPOTIFY.split("private func attemptAutomaticSpotifyWake", 1)[1].split("private func ensurePlayerStateSubscription", 1)[0]
    assert 'authorizeAndPlayURI("")' in auto
    assert "restoreTokenFromKeychain()" in auto
    assert "SpotifyTokenStore.clear()" not in auto
    assert "accessToken = nil" not in auto
    assert "automaticWakeCooldown" in SPOTIFY
    assert "you should not need to keep Spotify open" in MEDIA


def test_speed_limit_source_selector_has_current_enhanced_and_trace_osm_only():
    assert 'case current = "Current"' in SPEED
    assert 'case enhancedOSM = "Enhanced OSM"' in SPEED
    assert 'case traceOSM = "OSM Trace"' in SPEED
    assert 'case here = "HERE"' not in SPEED
    assert "SpeedLimitSourceMode.allCases" in VEHICLE
    assert "Picker(\"Speed-limit source\"" in VEHICLE
    assert "Current keeps the decompiled HUDWAY matcher unchanged" in VEHICLE
    assert "commercial API" in VEHICLE


def test_enhanced_osm_is_separate_from_original_matcher():
    assert "updateOriginalSegmentsIfNeeded" in SPEED
    assert "Original HUDWAY matcher loaded" in SPEED
    assert "updateEnhancedSegmentsIfNeeded" in SPEED
    assert 'maxspeedForward = "maxspeed:forward"' in SPEED
    assert 'maxspeedBackward = "maxspeed:backward"' in SPEED
    assert "enhancedCurrentSegmentID" in SPEED
    assert "Hold the previous accepted limit for one GPS sample" in SPEED


def test_osm_trace_is_local_matcher_with_no_paid_api_or_key_ui():
    assert "bestTraceSpeedLimit" in SPEED
    assert "traceLocations" in SPEED
    assert "traceCurrentSegmentID" in SPEED
    assert "confidenceMargin" in SPEED
    assert "OSM Trace accepted way=" in SPEED
    assert "parseSimpleConditionalMaxSpeed" in SPEED
    assert 'maxspeedConditional = "maxspeed:conditional"' in SPEED
    assert "routematching.hereapi.com" not in SPEED
    assert "HereAPIKeyStore" not in SPEED
    assert "Save HERE Key" not in VEHICLE
    assert "SecureField(" not in VEHICLE


def test_v9011_baseline_still_uses_cllocation_speed_and_v9012_can_consume_it_opt_in():
    # v90.12 deliberately enables an opt-in finite ambient warning from the same
    # CLLocation speed already used by the HUD. It must not imply OBD speed access.
    assert "CLLocation.speed" in SPEED
    assert "AMBIENT OVERSPEED WARNING" in VEHICLE
    assert "updateOverspeedWarning" in MONITOR
    assert "gpsSpeedMph > threshold" in MONITOR
