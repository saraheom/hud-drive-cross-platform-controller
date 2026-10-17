from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
CANVAS = (ROOT/'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
SNAP = (ROOT/'ios/HUDController/MapMode/HudMapModeSnapshot.swift').read_text()
SETTINGS = (ROOT/'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
RGD = (ROOT/'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()


def test_map_mode_is_the_only_user_visible_mainvideo_owner():
    starts = [line.strip() for line in APP.splitlines() if 'mainVideo.start(' in line]
    assert starts == ['self.mainVideo.start(reason: "physical Map Mode live source (optional)")']
    assert 'Start Live Preview (app only)' not in UI
    assert 'func startMainVideoPreview()' not in APP
    assert 'mainVideo.stop(reason: "live U2W Map Mode disabled — Map Mode owns MainVideo")' in APP
    assert 'guard hudU2WLiveRelayActive || mapModeActive else { return nil }' in APP


def test_live_map_is_drawn_even_without_navigation_and_overlays_remain_route_gated():
    assert 'if settings.showMap {' in CANVAS
    assert 'settings.showMap && snapshot.hasLiveRoute' not in CANVAS
    assert 'if snapshot.hasLiveRoute {' in CANVAS


def test_keep_decoder_bg_task_is_fixed_production_mode_with_lock_rebootstrap():
    assert 'backgroundProbeMode = .keepDecoderBackgroundTask' in SETTINGS
    assert 'mainVideo.configureBackgroundProbe(mode: .keepDecoderBackgroundTask)' in APP
    assert 'Map Mode Background Continuity Probe' not in UI
    assert 'Apply for next Map Mode session' not in UI
    assert 'Keep decoder + BG task' in UI
    assert 'lock-time -12903 detected' in VIDEO
    assert 'restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")' in VIDEO
    assert 'readOnlyRebootstrapCooldown' in VIDEO and 'startupSnapshotFetchTask' in VIDEO


def test_eta_sharing_uses_actual_custom_lane_renderer_visibility():
    assert 'laneGuidanceVisible: shouldDisplayActiveLanes()' in APP
    assert 'frozen.laneGuidanceVisible = shouldDisplayActiveLanes()' in APP
    assert 'settings.showLaneGuidance && snapshot.laneGuidanceVisible && !effectiveLaneValues.isEmpty' in CANVAS
    assert 'return !laneGuidanceAvailable' in CANVAS
    assert 'settings.etaUsesLanePositionWhenNoLanes ? .lanes : .eta' in CANVAS


def test_turn_distance_warning_is_continuous_shared_color_not_blink():
    assert 'distanceToManeuverMeters' in SNAP and 'distanceToManeuverMeters' in RGD
    assert 'turnDistanceWarningActive' in CANVAS
    assert 'snapshot.distanceToManeuverMeters' in CANVAS
    assert 'maneuverWarningThresholdFeet' in CANVAS
    assert '.foregroundStyle(turnDistanceWarningActive ? warningTextColor : .white)' in CANVAS
    assert 'speedWarningNumberRed' in CANVAS and 'warningTextColor' in CANVAS
    assert 'Turn distance warning' in UI
    assert 'Warning below' in UI
    assert 'Warning text color' in UI
    assert 'Preview blink' not in UI
    assert 'Blink count' not in UI
    assert 'warningHiddenTarget == .distance' not in CANVAS
