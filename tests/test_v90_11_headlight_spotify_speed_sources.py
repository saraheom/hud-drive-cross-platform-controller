from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
SPOTIFY = (ROOT / "ios/HUDController/Media/SpotifyMediaController.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
VEHICLE = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
MEDIA = (ROOT / "ios/HUDController/UI/MediaView.swift").read_text()


def test_headlight_state_uses_same_center_signal_as_hud_auto_brightness():
    assert "private func setAuthoritativeHeadlightPower" in MONITOR
    present = MONITOR.split("private func markPresent", 1)[1].split("private func markAbsent", 1)[0]
    absent = MONITOR.split("private func markAbsent", 1)[1].split("func rehydrateHUDState", 1)[0]
    assert "setAuthoritativeHeadlightPower(true" in present
    assert "HudCommands.autoBrightness(true)" in present
    assert "setAuthoritativeHeadlightPower(false" in absent
    assert "HudCommands.autoBrightness(false)" in absent
    assert "HUD brightness headlight OFF → day Door brightness" in MONITOR
    assert "HUD brightness headlight ON → night Door brightness" in MONITOR


def test_stale_headlight_breath_final_is_generation_safe():
    assert "headlightStateGeneration" in MONITOR
    assert "private func validBreathParticipant" in MONITOR
    assert "Skipped stale headlight Breath final" in MONITOR
    assert "headlightAnimatedEpochByID[id] == headlightPowerEpoch" in MONITOR


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


def test_speed_limit_source_selector_has_current_enhanced_osm_and_here():
    assert 'case current = "Current"' in SPEED
    assert 'case enhancedOSM = "Enhanced OSM"' in SPEED
    assert 'case here = "HERE"' in SPEED
    assert "SpeedLimitSourceMode.allCases" in VEHICLE
    assert "Picker(\"Speed-limit source\"" in VEHICLE
    assert "Current keeps the decompiled HUDWAY matcher unchanged" in VEHICLE


def test_enhanced_osm_is_separate_from_original_matcher():
    assert "updateOriginalSegmentsIfNeeded" in SPEED
    assert "Original HUDWAY matcher loaded" in SPEED
    assert "updateEnhancedSegmentsIfNeeded" in SPEED
    assert 'maxspeedForward = "maxspeed:forward"' in SPEED
    assert 'maxspeedBackward = "maxspeed:backward"' in SPEED
    assert "enhancedCurrentSegmentID" in SPEED
    assert "Hold the previous accepted limit for one GPS sample" in SPEED


def test_here_route_matching_is_opt_in_and_keychain_backed():
    assert "enum HereAPIKeyStore" in SPEED
    assert "kSecClassGenericPassword" in SPEED
    assert "routematching.hereapi.com/v8/match/routelinks" in SPEED
    assert 'URLQueryItem(name: "routeMatch", value: "1")' in SPEED
    assert 'URLQueryItem(name: "attributes", value: "APPLICABLE_SPEED_LIMIT(*)")' in SPEED
    assert "extractHereApplicableSpeedLimits" in SPEED
    assert "SecureField(" in VEHICLE
    assert "Save HERE Key" in VEHICLE
    assert "HERE key is stored in iPhone Keychain" in VEHICLE


def test_overspeed_ambient_warning_remains_unimplemented_until_obd_speed_is_available():
    # v90.11 intentionally adds no red warning state machine. Current speed source is still CLLocation.
    assert "CLLocation.speed" in SPEED
    assert "ambient overspeed warning remains disabled" in VEHICLE
    assert "OverspeedAmbient" not in MONITOR
