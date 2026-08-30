from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()


def test_field_verified_bledim_power_bit_is_not_the_old_inverted_mapping():
    assert "payload: [on ? 0x00 : 0x01]" in MODEL
    assert "payload: [on ? 0x01 : 0x00]" not in MODEL
    assert "payload 0x00 = physical ON" in MODEL
    assert "payload 0x01 = physical OFF" in MODEL


def test_bledim_no_flash_preload_and_brightness_only_terminal_are_preserved():
    prep = MONITOR.split("breathPrepareTasks[id] = Task", 1)[1].split("private func", 1)[0]
    assert "power-up breath preload RGB" in prep
    assert "power-up breath preload baseline" in prep
    assert "power-up breath prepare no-flash Power ON" in prep
    assert "power-up breath post-Power baseline" in prep
    assert prep.index("power-up breath preload RGB") < prep.index("power-up breath preload baseline") < prep.index("power-up breath prepare no-flash Power ON") < prep.index("power-up breath post-Power baseline")
    terminal = MONITOR.split("private func finalizeBreathSteadyState", 1)[1].split("private func runStartupAnimationIfNeeded", 1)[0]
    assert "power-up breath final (BLEDIM no-flash)" in terminal
    bledim_branch = terminal.split("if device.protocolKind == .bledim2 {", 1)[1].split("}", 1)[0]
    assert "sendPowerWhenReady" not in bledim_branch


def test_v9019_migrates_field_test_workaround_back_to_enabled_once():
    assert "migrateV9019BLEDIMPhysicalPowerSemanticsIfNeeded()" in MONITOR
    assert "HUD.Ambient.v90_19.bledimPhysicalPowerSemanticsMigrated" in MONITOR
    assert "pairedDevices[index].powerOn = true" in MONITOR
    assert "pairedDevices[index].role == .door || pairedDevices[index].role == .dashboard" in MONITOR


def test_philly_layers_use_schema_specific_fields_and_valid_envelope_query():
    assert 'geometryType", value: "esriGeometryEnvelope"' in SPEED
    assert 'URLQueryItem(name: "distance"' not in SPEED
    assert 'URLQueryItem(name: "units"' not in SPEED
    assert '? "OBJECTID,OBJECTID_1,STNM_LAB,STREET,SPLIMIT,SPEED_LIMITS"' in SPEED
    assert ': "OBJECTID,OBJECTID_1,STNM_LAB,STREET,SPLIMIT,SPEED_LIMITS,SpeedLimits_MPH"' in SPEED


def test_philly_layers_are_partial_failure_tolerant_and_backed_off():
    assert "async let postedTask = fetchPhiladelphiaLayer(0" in SPEED
    assert "async let residentialTask = fetchPhiladelphiaLayer(1" in SPEED
    assert "if successCount > 0" in SPEED
    assert "layersOK=%d/2" in SPEED
    assert "providerFailureRetrySeconds: TimeInterval = 12.0" in SPEED
    assert "philadelphiaLastFailureAt" in SPEED
    assert "improvedLastFailureAt" in SPEED
    assert "retry backoff=" in SPEED


def test_philly_gis_can_still_supply_limit_without_an_osm_candidate():
    matcher = SPEED.split("private func bestImprovedTraceSpeedLimit", 1)[1].split("private func acceptImprovedLimit", 1)[0]
    gis_accept = matcher.find("if let gisBest,")
    osm_fallback = matcher.find("if let confirmedOSM, let mph")
    assert gis_accept >= 0 and osm_fallback >= 0 and gis_accept < osm_fallback
    assert "philadelphiaSpeedSegments" in matcher
