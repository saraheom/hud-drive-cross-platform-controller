from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_production_speed_limit_packet_stays_rectangular_and_probe_can_send_style_zero():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    production = commands[commands.index("static func speedLimit(limit:"):commands.index("static func speedLimitProbe")]
    probe = commands[commands.index("static func speedLimitProbe"):commands.index("static func speedWarningThreshold")]
    assert "payload.append(HudProtocol.int32(1))" in production
    assert "static func speedLimitProbe(limit: Int, tolerance: Int = 0, style: Int)" in commands
    assert "min(1, style)" in probe


def test_temporary_probe_reproduces_original_automatic_sequence_without_mutating_live_matcher():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "func runOriginalAutomaticMarkerProbe(limitMph: Int, restoreProductionSign: Bool)" in speed
    assert "HudCommands.speedLimitProbe(limit: 0, tolerance: 0, style: 0)" in speed
    assert "HudCommands.speedWarningThreshold(limit)" in speed
    assert "live matcher state untouched" in speed
    assert "func runCurrentProductionMarkerProbe(limitMph: Int)" in speed
    assert "func restoreLiveSpeedLimitStateAfterMarkerProbe()" in speed


def test_temporary_marker_probe_ui_is_removed_but_diagnostic_engine_remains():
    ui = read("ios/HUDController/UI/VehicleView.swift")
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert 'section("SPEED MARKER PROBE — TEMPORARY")' not in ui
    assert 'Button("A — Exact original Automatic/TRAVEL sequence")' not in ui
    assert 'Button("Restore current HUD")' not in ui
    assert "func runOriginalAutomaticMarkerProbe" in speed
    assert "func restoreLiveSpeedLimitStateAfterMarkerProbe" in speed


def test_dashboard_profile_application_notifies_appstate_for_time_weather_reassert():
    obd = read("ios/HUDController/Vehicle/HudOBDController.swift")
    app = read("ios/HUDController/App/AppState.swift")
    assert "var onDashboardProfileApplied: ((String) -> Void)?" in obd
    assert 'onDashboardProfileApplied?("Freeride")' in obd
    assert 'onDashboardProfileApplied?("Navigation")' in obd
    assert "obd.onDashboardProfileApplied" in app
    assert "scheduleTimeWeatherPostDashboardReassert" in app
    assert "Task.sleep(for: .milliseconds(300))" in app
    assert '"TIME/WEATHER"' in app


def test_rehydration_sends_persisted_time_weather_after_dashboard_reconstruction():
    app = read("ios/HUDController/App/AppState.swift")
    phase2 = app[app.index("private func rehydrateUserHUD"):app.index("private func reassertDisplayCriticalState")]
    phase3 = app[app.index("private func reassertDisplayCriticalState"):]
    assert phase2.index("restoreDashboardOperatingMode") < phase2.index("applyTimeWeather()")
    assert phase3.index("obd.applyWidgetSelection()") < phase3.index("applyTimeWeather()")
    assert phase3.index("restoreDashboardOperatingMode") < phase3.index("applyTimeWeather()")


def test_disconnect_cancels_delayed_time_weather_reassert():
    app = read("ios/HUDController/App/AppState.swift")
    assert "self.timeWeatherPostDashboardTask?.cancel()" in app
    assert "self.timeWeatherPostDashboardTask = nil" in app
