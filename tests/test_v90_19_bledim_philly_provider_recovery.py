from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()


def test_v9020_restores_exact_v90172_bledim_power_mapping():
    assert "payload: [on ? 0x01 : 0x00]" in MODEL
    assert "payload: [on ? 0x00 : 0x01]" not in MODEL
    assert "exact field-proven v90.17.2 BLEDIM power mapping" in MODEL


def test_v9022_promotes_already_on_minimal_while_retaining_legacy_decoder_paths():
    prep = MONITOR.split("breathPrepareTasks[id] = Task", 1)[1].split("private func registerPowerOnCohortMember", 1)[0]
    assert '? .alreadyOnMinimal' in MONITOR
    assert 'case .v90172Baseline, .baselineHold, .brightnessOnlyFinish, .noTerminalCommit:' in prep
    terminal = MONITOR.split("private func finalizeBreathSteadyState", 1)[1].split("private func runStartupAnimationIfNeeded", 1)[0]
    assert 'case .v90172Baseline, .baselineHold:' in terminal
    assert 'power-up breath terminal Power ON' in terminal
    assert 'power-up breath terminal RGB' in terminal

def test_v9020_migrates_workaround_power_state_back_to_enabled_once():
    assert "migrateV9020BLEDIMKnownGoodRollbackIfNeeded()" in MONITOR
    assert "HUD.Ambient.v90_20.bledimKnownGoodRollbackMigrated" in MONITOR
    assert "pairedDevices[index].powerOn = true" in MONITOR
    assert "pairedDevices[index].role == .door || pairedDevices[index].role == .dashboard" in MONITOR

def test_philly_centerline_uses_current_schema_and_projection_safe_point_query():
    assert 'geometryType", value: "esriGeometryPoint"' in SPEED
    assert 'URLQueryItem(name: "distance", value: "650")' in SPEED
    assert 'URLQueryItem(name: "units", value: "esriSRUnit_Meter")' in SPEED
    assert 'URLQueryItem(name: "inSR", value: "4326")' in SPEED
    assert 'URLQueryItem(name: "outSR", value: "4326")' in SPEED
    assert 'TRANSPORTATION_street_segment/FeatureServer/0/query' in SPEED
    assert 'OBJECTID,SEGMENT_ID,FULL_STREET_NAME,STREET_NAME,SPEED_LIMIT,POSTED_SPEED_LIMIT,ROAD_CLASS,BUILT_STATUS' in SPEED


def test_philly_centerline_failure_is_backed_off_without_discarding_osm_path():
    assert "fetchPhiladelphiaStreetCenterlines" in SPEED
    assert "layersOK=1/1" in SPEED
    assert "providerFailureRetrySeconds: TimeInterval = 12.0" in SPEED
    assert "philadelphiaLastFailureAt" in SPEED
    assert "improvedLastFailureAt" in SPEED
    assert "retry backoff=" in SPEED


def test_philly_gis_can_still_supply_limit_without_an_osm_candidate():
    matcher = SPEED.split("private func bestImprovedTraceSpeedLimit", 1)[1].split("private func acceptImprovedLimit", 1)[0]
    gis_accept = matcher.find("if let gisCandidate = {")
    osm_fallback = matcher.find("if let confirmedOSM, let mph")
    assert gis_accept >= 0 and osm_fallback >= 0 and gis_accept < osm_fallback
    assert "philadelphiaSpeedSegments" in matcher
