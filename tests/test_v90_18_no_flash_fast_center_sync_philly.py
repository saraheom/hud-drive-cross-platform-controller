from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
VEHICLE = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()
AMBIENT_VIEW = (ROOT / 'ios/HUDController/UI/AmbientLightingView.swift').read_text()


def test_bledim_normal_breath_completion_is_brightness_only_no_flash():
    block = MONITOR.split('private func finalizeBreathSteadyState', 1)[1].split('private func runStartupAnimationIfNeeded', 1)[0]
    bledim = block.split('if device.protocolKind == .bledim2', 1)[1].split('let powerSent =', 1)[0]
    assert 'power-up breath final (BLEDIM no-flash)' in bledim
    assert 'applyRuntimeBrightnessWhenReady' in bledim
    assert 'sendPowerWhenReady' not in bledim
    assert 'sendColorWhenReady' not in bledim


def test_bledim_preloads_state_before_power_and_reasserts_baseline_after_power():
    prep = MONITOR.split('private func queuePowerUpBreath', 1)[1].split('} else {', 1)[0]
    assert prep.index('power-up breath preload RGB') < prep.index('power-up breath preload baseline')
    assert prep.index('power-up breath preload baseline') < prep.index('power-up breath prepare no-flash Power ON')
    assert prep.index('power-up breath prepare no-flash Power ON') < prep.index('power-up breath post-Power baseline')


def test_center_presence_drives_hud_and_door_without_dashboard_delay():
    present = MONITOR.split('private func markPresent', 1)[1].split('private func markAbsent', 1)[0]
    absent = MONITOR.split('private func markAbsent', 1)[1].split('func rehydrateHUDState', 1)[0]
    commit = MONITOR.split('private func commitConfirmedHeadlightPower', 1)[1].split('private func noteHeadlightPowerSeen', 1)[0]
    assert 'commitConfirmedHeadlightPower(true' in present
    assert 'commitConfirmedHeadlightPower(false' in absent
    assert 'Center presence → Auto brightness ON' in commit
    assert 'Center absence → Auto brightness OFF' in commit
    assert 'Center present → night Door brightness' in commit
    assert 'Center absent → day Door brightness' in commit
    assert 'Dashboard+Center diagnostic consensus' not in commit


def test_automatic_door_day_night_fade_is_fast_and_separate_from_manual_fade():
    assert 'automaticDoorDayNightTransitionSeconds: TimeInterval = 1.0' in MONITOR
    block = MONITOR.split('private func applyCurrentDoorDayNightTarget', 1)[1].split('private func transitionDoorBrightness', 1)[0]
    assert 'over: automaticDoorDayNightTransitionSeconds' in block
    manual = MONITOR.split('func setBrightness(_ id: UUID', 1)[1].split('func setStartupAnimationEnabled', 1)[0]
    assert 'over: brightnessTransitionSeconds' in manual
    assert 'dedicated fast 1.0 s fade' in AMBIENT_VIEW


def test_sync_cohort_is_registered_before_bledim_boot_settle_and_uses_common_t0():
    run = MONITOR.split('private func runStartupAnimationIfNeeded', 1)[1].split('private func queuePowerUpBreath', 1)[0]
    assert run.index('registerPowerOnCohortMember(id)') < run.index('scheduleBLEDIMBootSettleReassert')
    cohort = MONITOR.split('private func registerPowerOnCohortMember', 1)[1].split('private func releasePendingSyncCohortToIndependentBreaths', 1)[0]
    assert 'powerOnSyncWindowSeconds' in cohort
    assert 'powerOnSyncPreparationGraceSeconds' in cohort
    assert 'syncCohortExpectedIDs.isSubset(of: self.synchronizedBreathIDs)' in cohort
    assert 'Power-on cohort common T0' in cohort
    cleanup = MONITOR.split('private func removeFromActiveBreath', 1)[1].split('private func scheduleStartupSessionReset', 1)[0]
    assert 'synchronizedBreathIDs.isEmpty && syncCohortExpectedIDs.isEmpty' in cleanup


def test_only_three_requested_speed_sources_are_exposed():
    enum = SPEED.split('enum SpeedLimitSourceMode', 1)[1].split('@MainActor', 1)[0]
    assert 'case current = "Current"' in enum
    assert 'case traceOSM = "OSM Trace"' in enum
    assert 'case improvedTracePhilly = "Improved + Philly GIS"' in enum
    assert 'case enhancedOSM' not in enum
    assert 'case here' not in enum
    assert 'Improved + Philly GIS' in VEHICLE


def test_improved_mode_loads_untagged_roads_and_clears_stale_sign():
    improved_query = SPEED.split('private func updateImprovedSegmentsIfNeeded', 1)[1].split('private static func makeImprovedSegment', 1)[0]
    assert 'way[highway~' in improved_query
    assert '[maxspeed]' not in improved_query
    assert 'residential' in improved_query and 'living_street' in improved_query
    assert 'improvedDisplayGraceSeconds: TimeInterval = 4.0' in SPEED
    assert 'clearDisplayedLimit(reason:' in SPEED
    assert 'Improved Trace lost a fresh road match' in SPEED


def test_philadelphia_gis_and_motorway_protection_are_present():
    assert 'services8.arcgis.com/6pr2WaSuWO79zliF/ArcGIS/rest/services/SpeedLimits/FeatureServer/' in SPEED
    assert 'SPEED_LIMITS,SpeedLimits_MPH' in SPEED
    assert 'async let posted = fetchPhiladelphiaLayer(0' in SPEED
    assert 'async let residential = fetchPhiladelphiaLayer(1' in SPEED
    assert '?? (residential ? 25 : nil)' in SPEED
    assert '["motorway", "motorway_link"].contains(confirmedOSM.segment.highway)' in SPEED
    assert 'source: "OSM explicit motorway"' in SPEED
    assert 'Philadelphia residential GIS' in SPEED
    assert 'Philadelphia posted-speed GIS' in SPEED


def test_improved_geometry_scorer_does_not_treat_greatest_finite_as_a_match():
    block = SPEED.split('private func traceGeometryMatch', 1)[1].split('private func bestImprovedTraceSpeedLimit', 1)[0]
    assert 'var pointBest: Double?' in block
    assert 'if let pointBest {' in block
    assert 'Double.greatestFiniteMagnitude' not in block

def test_inferred_philly_residential_limit_is_display_only_for_warning_safety():
    assert 'let explicitSpeed = Self.philadelphiaValidSpeed(attributes["SPEED_LIMITS"])' in SPEED
    assert 'private nonisolated static func philadelphiaIntValue' in SPEED
    assert 'private nonisolated static func philadelphiaValidSpeed' in SPEED
    assert 'func intValue(_ value: Any?)' not in SPEED
    assert 'speedWasExplicit: explicitSpeed != nil' in SPEED
    assert 'warningEligible: !inferredResidential' in SPEED
    assert 'Display-only inferred speed limit — disable native warning threshold' in SPEED
    assert 'currentLimitWarningEligible' in SPEED
    refresh = SPEED.split('private func refreshWarningLimitAvailability', 1)[1].split('private func updateProviderDataIfNeeded', 1)[0]
    assert 'currentLimitWarningEligible' in refresh


def test_clearing_or_switching_limit_source_also_clears_native_warning_threshold():
    assert 'Clear stale speed-limit warning threshold' in SPEED
    assert 'Speed-limit source changed → native warning OFF until fresh limit' in SPEED
    assert 'Speed-limit session prime → native warning OFF until fresh limit' in SPEED
