from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_native_speed_marker_uses_stock_display_speed_warning_packet():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "static func speedWarningThreshold(_ value: Int)" in commands
    assert "command: 2, p1: 9, p2: 9" in commands
    assert "func reassertOriginalSpeedMarker(reason: String)" in speed
    assert "sendOriginalAutomaticSpeedWarning(legalLimitMph: currentSpeedLimitMph)" in speed
    assert '"SPEED MARKER"' in speed
    assert "stock red threshold arc" in speed
    assert "HudCommands.speedWarningThreshold(0)" in speed


def test_navigation_mode_change_reasserts_stock_marker_after_renderer_swap():
    nav = read("ios/HUDController/Navigation/HudNavigationController.swift")
    app = read("ios/HUDController/App/AppState.swift")
    assert "var onNavigationModeChanged: ((Bool) -> Void)?" in nav
    assert "onNavigationModeChanged?(true)" in nav
    assert "onNavigationModeChanged?(false)" in nav
    assert "navigation.onNavigationModeChanged" in app
    assert "Task.sleep(for: .milliseconds(150))" in app
    assert '"Navigation renderer activated"' in app
    assert '"Freeride renderer activated"' in app
    assert "reassertOriginalSpeedMarker" in app


def test_vehicle_ui_exposes_native_marker_state_and_manual_widget_reasserts():
    ui = read("ios/HUDController/UI/VehicleView.swift")
    assert 'LabeledContent("Native speed marker"' in ui
    assert "nativeSpeedMarkerStatus" in ui
    assert 'reassertOriginalSpeedMarker(reason: "Freeride widget profile applied")' in ui
    assert 'reassertOriginalSpeedMarker(reason: "Navigation widget profile applied")' in ui
    assert "DisplaySpeedWarning threshold" in ui
    assert "small red speed-limit arc" in ui


def test_manual_color_write_restores_resolved_preferred_brightness():
    ambient = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    assert "manualColorBrightnessRestoreSeconds: TimeInterval = 1.0" in ambient
    assert "await self.restorePreferredBrightnessAfterManualColor" in ambient
    assert "let target = steadyBrightnessTarget(for: device)" in ambient
    assert "activeBreathReturnBrightness[id] = target" in ambient
    assert "cancelBrightnessTransition(for: id)" in ambient


def test_bledim_color_change_models_physical_full_brightness_then_fades_back():
    ambient = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    assert "case .bledim2:" in ambient
    assert "pairedDevices[index].lastAppliedBrightness = 100" in ambient
    assert 'reason: "post-RGB preferred brightness restore"' in ambient
    assert "over: manualColorBrightnessRestoreSeconds" in ambient
    assert "BLEDIM RGB assumed physical 100%" in ambient


def test_lotus_color_change_reasserts_target_without_fabricating_full_brightness():
    ambient = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    assert "case .lotusLantern:" in ambient
    assert "await applyRuntimeBrightnessWhenReady(" in ambient
    assert "Lotus RGB steady target reasserted" in ambient


def test_group_color_keeps_per_device_restore_path_and_ui_documents_it():
    ambient = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    ui = read("ios/HUDController/UI/AmbientLightingView.swift")
    assert "func setGroupColor(_ groupID: UUID, color: AmbientRGB)" in ambient
    assert "for id in group.memberIDs { setColor(id, color: color) }" in ambient
    assert "each member to its own resolved steady brightness" in ui
    assert "Door therefore returns to its current Day/Night target" in ui


def test_manual_color_is_deferred_during_active_overspeed_overlay():
    ambient = read("ios/HUDController/Vehicle/AmbientLightMonitor.swift")
    assert "if self.overspeedWarningActiveID == id" in ambient
    assert "hardware write deferred until overspeed restore" in ambient
