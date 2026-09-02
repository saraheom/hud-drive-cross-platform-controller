from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
VIEW = (ROOT / 'ios/HUDController/UI/AmbientLightingView.swift').read_text()
MEDIA = (ROOT / 'docs/MEDIA_NAVIGATION_SOURCES.md').read_text()


def block(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def test_automatic_breath_is_gated_by_raw_obd_not_hud_engine_diagnostic():
    run = block(MONITOR, 'private func runStartupAnimationIfNeeded', 'private func prepareAutomaticSyncMember')
    hud = block(MONITOR, 'func hudTransportPowerSignal', 'func obdPowerSignal')
    assert 'guard obdEnginePowerSignalPresent else' in run
    assert 'Automatic Breath held until OBD connection' in run
    assert 'enginePowerPresent' not in run
    assert 'it no longer arms ambient animation' in hud
    assert 'engineStartupSyncCandidateActive = true' not in hud


def test_obd_connection_arms_exactly_one_all_three_startup_opportunity():
    obd = block(MONITOR, 'func obdPowerSignal', 'private func currentOBDTargetName')
    schedule = block(MONITOR, 'private func scheduleEngineStartupSynchronization', 'private func beginEngineStartupFullSyncCohort')
    assert 'scheduleEngineStartupSynchronization(source: "OBD connected")' in obd
    assert 'engineStartupSyncCompletedForCurrentEngineSession = false' in obd
    assert 'requiredRoles: Set<AmbientLightRole> = [.centerConsole, .door, .dashboard]' in schedule
    assert 'roles == requiredRoles' in schedule
    assert 'engineStartupMaxWaitSeconds: TimeInterval = 10.0' in MONITOR


def test_startup_never_releases_partial_or_late_catchup_breath():
    full = block(MONITOR, 'private func beginEngineStartupFullSyncCohort', 'private func confirmEnginePowerOn')
    assert 'ready == expectedNow, ready.count == 3' in full
    assert 'strict all-three readiness not met' in full
    assert 'no partial/late Breath' in full
    assert 'OBD STARTUP FULL-COHORT common T0 ready=3 late=0' in full


def test_later_headlight_on_pairs_center_and_dashboard_but_leaves_active_door_out():
    barrier = block(MONITOR, 'private func beginHeadlightTransitionSyncCohort', 'private func registerPowerOnCohortMember')
    assert 'joiningRoles.contains(.centerConsole) || joiningRoles.contains(.dashboard)' in barrier
    assert 'for role in [AmbientLightRole.centerConsole, AmbientLightRole.dashboard]' in barrier
    assert 'isJoiningHeadlightTransition(peer) || !isPhysicallyPresentOrConnecting(peer.id)' in barrier
    assert 'Door is enrolled only when Door itself is newly joining' in barrier
    assert 'untouchedAlreadyActive' in barrier
    assert 'HEADLIGHT STRICT-COHORT common T0' in barrier


def test_headlight_cohort_skips_instead_of_splitting_when_member_never_ready():
    barrier = block(MONITOR, 'private func beginHeadlightTransitionSyncCohort', 'private func registerPowerOnCohortMember')
    assert 'headlightStrictReadyTimeoutSeconds: TimeInterval = 10.0' in MONITOR
    assert 'ready == expectedNow' in barrier
    assert 'HEADLIGHT STRICT-COHORT skipped' in barrier
    assert 'no partial/late Breath' in barrier
    assert 'self.startIndividualBreathSession' not in barrier


def test_speed_cache_is_bounded_same_road_display_only_and_turn_invalidated():
    assert 'improvedRoadLimitCacheMaxAgeSeconds: TimeInterval = 90.0' in SPEED
    assert 'improvedRoadLimitCacheMaxDistanceMeters: CLLocationDistance = 1_200' in SPEED
    assert 'improvedRoadLimitCacheMaxCourseDeltaDegrees: Double = 35.0' in SPEED
    matcher = block(SPEED, 'private func bestImprovedTraceSpeedLimit', 'private func acceptImprovedLimit')
    assert 'cached same-road limit hold' in matcher
    assert 'improvedDisplayContinuityFresh = true' in matcher
    assert 'currentLimitWarningEligible = false' in matcher
    assert 'Cached same-road display hold — disable native warning threshold' in matcher
    assert 'improvedRoadLimitCacheIdentity = nil' in matcher


def test_philly_diagnostics_separate_raw_speed_geometry_and_parsed_counts():
    assert 'rawFeatures=%d' in SPEED
    assert 'featuresWithSpeed=%d' in SPEED
    assert 'featuresWithGeometry=%d' in SPEED
    assert 'parsedSegments=%d' in SPEED
    assert 'rawFeatures: features.count' in SPEED
    assert 'featuresWithSpeed: featuresWithSpeed' in SPEED
    assert 'featuresWithGeometry: featuresWithGeometry' in SPEED


def test_ui_and_media_roadmap_match_obd_sync_and_carplay_adapter_direction():
    assert 'Automatic Breath is OBD-gated' in VIEW
    assert 'There is no late independent catch-up Breath' in VIEW
    assert 'CarPlay adapter' in MEDIA
    assert '0x5000/0x5001' in MEDIA
    assert '0x5200' in MEDIA and '0x5204' in MEDIA
    assert 'ScreenCaptureKit' in MEDIA and 'fallback' in MEDIA.lower()
