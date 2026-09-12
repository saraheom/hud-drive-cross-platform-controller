from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_recovered_speed_visibility_and_gauge_packets_are_exposed_only_for_probe_use():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    assert "static func speedInformationVisible(_ enabled: Bool)" in commands
    assert "command: 2, p1: 9, p2: 3" in commands
    assert "static func speedGaugeEnabled(_ enabled: Bool)" in commands
    assert "command: 2, p1: 9, p2: 12" in commands
    assert "diagnostic probe rather than a production assumption" in commands


def test_d0_d3_expanded_probe_sequences_are_present_and_do_not_mutate_matcher_state():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "func runSpeedGaugeZeroProbe()" in speed
    assert "HudCommands.speedGaugeEnabled(true)" in speed
    assert "HudCommands.speedWarningThreshold(0)" in speed
    assert "func runSpeedGaugeStockChainProbe(limitMph: Int)" in speed
    assert "func runSpeedGaugeEdgeProbe(limitMph: Int)" in speed
    assert "HudCommands.speedGaugeEnabled(false)" in speed
    assert "Task.sleep(for: .milliseconds(350))" in speed
    assert "func runStockFreerideGaugeEdgeProbe(limitMph: Int)" in speed
    assert 'HudCommands.dashboard(left: "Speedo", center: "Simple", right: "Weather", navigationLayout: false)' in speed
    assert 'HudCommands.navigationState(false)' in speed
    assert "private func sendSpeedGaugeStockChain(limit: Int, prefix: String)" in speed
    assert "speedLimitProbe(limit: limit, tolerance: 0, style: 0)" in speed
    assert "live matcher state untouched" in speed


def test_speed_gauge_probe_engine_remains_but_temporary_vehicle_ui_is_removed():
    ui = read("ios/HUDController/UI/VehicleView.swift")
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    for label in [
        'Button("D0 — Gauge ON + zero threshold")',
        'Button("D1 — Gauge ON + full stock speed chain")',
        'Button("D2 — Gauge OFF→ON edge + stock chain")',
        'Button("D3 — Exact stock Freeride + gauge edge (parked)")',
        'Button("Restore current HUD")',
    ]:
        assert label not in ui
    assert "func runSpeedGaugeZeroProbe" in speed
    assert "func runSpeedGaugeEdgeProbe" in speed

def test_time_weather_off_cold_session_is_off_only_after_phase3():
    app = read("ios/HUDController/App/AppState.swift")
    assert "private var timeWeatherColdOffSyncTask" in app
    assert "private func scheduleTimeWeatherColdOffSynchronization(reason: String)" in app
    assert "guard !settings.showTimeWeather else { return }" in app
    assert "Task.sleep(for: .milliseconds(650))" in app
    assert "Cold-session delayed OFF-only reassert" in app
    assert "no transient ON packet sent" in app
    assert "Cold-session time/weather sync edge -> transient ON" not in app

def test_time_weather_sync_is_cancelled_on_disconnect_and_new_rehydration():
    app = read("ios/HUDController/App/AppState.swift")
    disconnect = app[app.index("bluetooth.onTransportDisconnected"):app.index("/// The original HUDWAY protocol")]
    assert "self.timeWeatherColdOffSyncTask?.cancel()" in disconnect
    assert "self.timeWeatherColdOffSyncTask = nil" in disconnect
    schedule = app[app.index("private func scheduleHUDRehydration"):app.index("private func rehydrateBaseHUD")]
    assert "timeWeatherColdOffSyncTask?.cancel()" in schedule
    assert "timeWeatherColdOffSyncTask = nil" in schedule


def test_restore_current_hud_reapplies_dashboard_time_weather_and_live_speed_state():
    app = read("ios/HUDController/App/AppState.swift")
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    restore = app[app.index("func restoreHUDAfterSpeedMarkerProbe()") : app.index("// MARK: - Original HUDWAY display calibration")]
    assert "obd.applyWidgetSelection()" in restore
    assert "restoreDashboardOperatingMode" in restore
    assert "applyTimeWeather()" in restore
    assert "speedEngine.restoreLiveSpeedLimitStateAfterMarkerProbe()" in restore
    assert 'HudCommands.speedGaugeEnabled(false)' in speed
