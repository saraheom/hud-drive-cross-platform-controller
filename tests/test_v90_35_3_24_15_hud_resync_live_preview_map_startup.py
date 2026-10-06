from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
NAV = (ROOT / "ios/HUDController/Navigation/HudNavigationController.swift").read_text()
RGD = (ROOT / "ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
ROOTVIEW = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()


def test_hud_reboot_rehydrates_current_carplay_navigation_payload():
    assert 'routeGuidance.reassertPhysicalHUD(reason: "HUD rehydrate phase 2 / \\(reason)")' in APP
    assert 'routeGuidance.reassertPhysicalHUD(reason: "HUD rehydrate phase 3 / \\(reason)")' in APP
    assert 'func reassertPhysicalHUD(reason: String)' in RGD
    assert 'navigation.reassertNavigationMode(owner: .carPlayAdapter, reason: reason, delayed: true)' in RGD
    assert 'navigation.sendETA(arrivalTimeMilliseconds: arrivalMs, owner: .carPlayAdapter)' in RGD
    assert 'navigation.sendCurrent(owner: .carPlayAdapter)' in RGD
    assert 'publishLiveLaneGuidance(snapshot, source: selectedSource)' in RGD


def test_live_route_sparse_navigation_mode_assurance_bounds_missed_mode_packet():
    assert 'func assurePhysicalNavigationMode' in NAV
    assert 'minimumInterval: TimeInterval = 8.0' in NAV
    assert 'navigation.assurePhysicalNavigationMode(' in RGD
    assert 'minimumInterval: 8.0' in RGD
    assert 'physicalNavigationModeAllowed' in NAV
    assert 'return !self.hudU2WLiveRelayActive' in APP


def test_app_only_live_preview_never_starts_physical_hud_casting():
    start = APP.index('func startMainVideoPreview()')
    end = APP.index('func stopMainVideoPreview', start)
    block = APP[start:end]
    assert 'mainVideo.start(reason: "app-only live preview")' in block
    assert 'HudCommands.kivicMode(6)' not in block
    assert 'u2whud-start.cgi' not in block
    assert 'hudU2WFrameRelay.start()' not in block
    assert 'Start Live Preview (app only)' in UI
    assert 'physical HUD mode unchanged' in APP


def test_preview_is_explicit_but_background_no_longer_intentionally_stops_it():
    assert 'mainVideoPreviewActive = false' in APP
    background = ROOTVIEW.split("case .background:", 1)[1].split("default:", 1)[0]
    assert 'state.hudU2WLiveRelayActive || state.mainVideoPreviewActive' in background
    assert 'state.stopMainVideoPreview(reason: "app background")' not in background
    assert 'Route Guidance endpoint reachable; MainVideo intentionally idle unless Map Mode is explicitly enabled' in APP


def test_v2414_false_failed_safe_during_tcp_connect_is_removed():
    old = 'if self.adapterRelayVersion.contains("v8.31") {\n                        self.transportPhase = "FAILED_SAFE"\n                        self.status = "Live map disconnected — Navigation remains active"'
    assert old not in VIDEO
    assert 'TCP_PREPARING / TCP_WAITING /' in VIDEO
    assert 'authority for real failed/EOF states' in VIDEO


def test_map_mode_uses_fallback_first_physical_jpeg_prewarm_with_bounded_recovery():
    assert 'for _ in 0..<70' in APP
    assert 'up to 7 s including one bounded reconnect' in APP
    assert 'hudU2WFrameRelay.ensureConnection(reason: "Map Mode prewarm did not deliver first JPEG")' in APP
    assert 'for _ in 0..<30' in APP
    assert 'guard firstFrameDelivered else' in APP
    assert 'physical Map Mode no longer depends on MainVideo readiness' in APP


def test_map_mode_attempt_generation_fences_stale_cancellation():
    assert 'private var hudU2WMapModeAttemptGeneration: UInt64 = 0' in APP
    assert 'self.hudU2WMapModeAttemptGeneration == mapModeAttemptGeneration' in APP
    assert APP.count('hudU2WMapModeAttemptGeneration &+= 1') >= 2


def test_map_mode_stop_preserves_only_explicit_preview():
    assert 'if mainVideoPreviewActive {' in APP
    assert 'Physical Map Mode stopped; app-only preview retained' in APP
    assert 'mainVideo.stop(reason: "live U2W Map Mode disabled — restore Navigation-only adapter load")' in APP


def test_current_version_and_pairing_marker():
    assert 'appVersion=v90.35.3.24.25' in APP
    assert 'v90.35.3.24.25 pairs with U2W v8.37 Forensic Seam Capture + unchanged v8.35 helper (injection deferred) + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay' in UI
