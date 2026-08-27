from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
MODEL = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
SPOTIFY = (ROOT / "ios/HUDController/Media/SpotifyMediaController.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
ROOT_VIEW = (ROOT / "ios/HUDController/UI/RootView.swift").read_text()
VEHICLE = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()


def block(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def test_spotify_automatic_app_wake_requires_hud_or_obd_vehicle_evidence():
    assert "automaticVehicleWakeAllowed" in SPOTIFY
    wake = block(SPOTIFY, "private func attemptAutomaticSpotifyWake", "private func ensurePlayerStateSubscription")
    assert "guard automaticVehicleWakeAllowed else" in wake
    assert "Automatic Spotify app wake suppressed outside vehicle session" in wake
    assert "let allowed = bluetooth.state == .connected || obd.connected" in APP
    assert 'updateSpotifyVehicleWakeGate(reason: "HUD connected")' in APP
    assert 'updateSpotifyVehicleWakeGate(reason: "HUD disconnected")' in APP
    assert 'connected ? "OBD connected" : "OBD disconnected"' in APP
    assert 'updateSpotifyVehicleWakeGate(reason: "root view appeared")' in ROOT_VIEW
    assert 'updateSpotifyVehicleWakeGate(reason: "app became active")' in ROOT_VIEW


def test_dashboard_interrupted_breath_rearms_inside_same_headlight_epoch():
    disconnect = block(MONITOR, "didDisconnectPeripheral peripheral: CBPeripheral", "// MARK: - CBPeripheralDelegate")
    assert "interruptedHeadlightAnimation" in disconnect
    assert "headlightAnimatedEpochByID[id] = nil" in disconnect
    assert "restartHeadlightBreathOnReconnectIDs.insert(id)" in disconnect
    assert "Interrupted headlight Breath will restart on reconnect" in disconnect
    assert 'noteHeadlightPowerSeen(id, reason: "didConnect")' in MONITOR
    assert "headlightAnimatedEpochByID[id] != headlightPowerEpoch" in MONITOR


def test_headlight_edge_cancels_entire_old_shared_breath_timeline():
    assert "private func cancelSynchronizedBreathForHeadlightEdge" in MONITOR
    edge = block(MONITOR, "private func cancelSynchronizedBreathForHeadlightEdge", "private func scheduleStartupSessionReset")
    assert "synchronizedBreathTask?.cancel()" in edge
    assert "activeBreathIDs.removeAll()" in edge
    assert "activeBreathStartBrightness.removeAll()" in edge
    assert "activeBreathReturnBrightness.removeAll()" in edge
    assert "breathPrepareTasks[doorID]?.cancel()" in edge
    power = block(MONITOR, "private func setAuthoritativeHeadlightPower", "private func noteHeadlightPowerSeen")
    assert 'cancelSynchronizedBreathForHeadlightEdge(reason: "authoritative headlight ON")' in power
    assert 'cancelSynchronizedBreathForHeadlightEdge(reason: "authoritative headlight OFF")' in power


def test_headlight_reconnect_reasserts_power_and_steady_brightness_twice():
    restore = block(MONITOR, "private func restoreDeviceState", "private func runStartupAnimationIfNeeded")
    assert "headlight reconnect safety reassert" in restore
    assert "sendPowerWhenReady(id, on: true" in restore
    assert "Task.sleep(for: .milliseconds(180))" in restore
    prep = block(MONITOR, "private func queuePowerUpBreath", "private func validBreathParticipant")
    assert "requestedHeadlightEpoch" in prep
    assert "requestedHeadlightGeneration" in prep
    assert "requestStillValid()" in prep
    assert "power-up breath safety reassert" in prep
    assert "power-up breath safety baseline" in prep


def test_finite_overspeed_warning_uses_exact_user_requested_formula_and_no_sign_means_no_warning():
    assert 'case door = "Door"' in MODEL
    assert 'case dashboard = "Dashboard"' in MODEL
    update = block(MONITOR, "func updateOverspeedWarning", "private func triggerOverspeedWarning")
    assert "let threshold = speedLimitMph + offset" in update
    assert "let above = gpsSpeedMph > threshold" in update
    assert "let crossedUp = above && !overspeedAboveThreshold" in update
    assert "if !available" in update
    assert "speed-limit sign unavailable" in update
    assert "When a valid sign first appears, establish a baseline without warning" in update
    assert "fall below and recross" in update


def test_warning_ui_exposes_offset_light_brightness_pulse_count_and_duration():
    assert "AMBIENT OVERSPEED WARNING" in VEHICLE
    assert "Finite red-light warning" in VEHICLE
    assert "Warning light" in VEHICLE
    assert "Offset above limit" in VEHICLE
    assert "in: 0...20" in VEHICLE
    assert "Warning brightness" in VEHICLE
    assert 'Text("2×").tag(2)' in VEHICLE
    assert 'Text("3×").tag(3)' in VEHICLE
    assert "Pulse duration / cycle" in VEHICLE
    assert "No speed-limit sign — disabled" in VEHICLE


def test_warning_never_uses_power_off_and_dashboard_requires_headlight_power():
    warning = block(MONITOR, "private func triggerOverspeedWarning", "// MARK: - Connection management")
    assert "sendPowerWhenReady(id, on: true" in warning
    assert "sendPowerWhenReady(id, on: false" not in warning
    assert "BLEDIM2Protocol.power(false" not in warning
    assert "if role == .dashboard, !headlightPowerSessionActive" in warning
    assert "headlightStateGeneration == capturedHeadlightGeneration" in warning
    assert "headlight power OFF during dashboard warning" in MONITOR


def test_warning_failure_and_completion_restore_current_semantic_state_with_safety_reassert():
    warning = block(MONITOR, "private func triggerOverspeedWarning", "// MARK: - Connection management")
    assert "abortOverspeedWarningTask" in warning
    assert "overspeed restore safety reassert" in warning
    steady = block(MONITOR, "private func steadyBrightnessAfterWarning", "private func restoreAfterOverspeedWarning")
    assert "doorTargetBrightness(night: vehicleHeadlightsActive)" in steady
    door = block(MONITOR, "private func applyCurrentDoorDayNightTarget", "private func transitionDoorBrightness")
    assert "Door day/night target changed" in door
    assert "deferred until overlay restores" in door


def test_speed_limit_warning_requires_fresh_live_match_not_cached_prior_drive_value():
    assert "speedLimitAvailableForWarning" in SPEED
    assert "lastResolvedLimitAt" in SPEED
    assert "warningLimitFreshnessSeconds" in SPEED
    assert "12.0" in SPEED
    assert "A previous-drive UserDefaults value must never arm" in SPEED
    assert "refreshWarningLimitAvailability" in SPEED
    assert "speedLimitAvailableForWarning" in VEHICLE


def test_speed_engine_is_wired_to_ambient_warning_and_still_uses_gps_not_obd_speed():
    assert "CLLocation.speed" in SPEED
    assert "onSpeedStateChanged" in SPEED
    assert "ambientLight?.updateOverspeedWarning" in APP
    assert "gpsSpeedMph: speedMph" in APP
    assert "speedLimitMph: limitMph" in APP
    assert "limitAvailable: available" in APP
