"""v24.35 contract checks for bounded automatic Map Mode, stock HUD info and tidy OBD UI.
Source inspections complement but do not replace iOS compilation or actual HUD validation.
"""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
VEH = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
CMD = (ROOT / "ios/HUDController/Protocol/HudCommands.swift").read_text()


def test_startup_poll_is_read_only_and_checks_http_not_internet_reachability():
    auto = APP.split('private func scheduleAutomaticMapModeStart(reason:', 1)[1].split('func startHUDU2WSTAHomeProbe', 1)[0]
    assert 'u2whud-status.cgi' in auto
    assert 'URLSession.shared.data(for: request)' in auto
    assert 'request.timeoutInterval = 3' in auto
    assert 'Date() < self.automaticMapModeRetryDeadline' in auto
    assert 'let status = (response as? HTTPURLResponse)?.statusCode ?? 0' in auto
    assert 'ready = (200...299).contains(status)' in auto
    assert 'while !Task.isCancelled' in auto
    assert 'bluetooth.state == .connected' in auto
    assert 'startHUDU2WSTAHomeProbe(ssid: credentials.ssid, password: credentials.password, automaticAttempt: true)' in auto
    assert 'kivicMode(6)' not in auto
    assert 'beginMapModeDirectOBDOwnership' not in auto


def test_failed_start_rearms_auto_but_preserves_stock_obd_until_ack():
    start = APP.split('func startHUDU2WSTAHomeProbe(ssid:', 1)[1].split('private func scheduleHUDU2WAutomaticJoinRecovery', 1)[0]
    assert 'automaticStartFailure = "adapter unreachable"' in start
    assert 'automaticStartFailure = "HTTP \(code)"' in start
    assert 'self.scheduleAutomaticMapModeStart(reason: "relay start retry")' in start
    assert start.index('let (data, response) = try await URLSession.shared.data(for: request)') < start.index('self.beginMapModeDirectOBDOwnership')
    assert start.index('guard (200...299).contains(code) else') < start.index('self.beginMapModeDirectOBDOwnership')
    assert 'Date() < self.automaticMapModeRetryDeadline' in start
    assert 'self.hudU2WSTAStatusTask = nil' in start


def test_off_disconnect_and_manual_retry_cancel_safely():
    assert 'automaticMapModeScheduleGeneration &+= 1' in APP
    assert 'automaticMapModeStartTask?.cancel()' in APP
    assert 'automaticMapModeRetryDeadline = .distantPast' in APP
    assert 'hudU2WSTAStatusTask?.cancel()' in APP
    assert 'self.automaticMapModeRetryDeadline = .distantPast' in APP
    assert 'guard automaticMapModeEnabled' in APP


def test_native_stock_info_not_music_or_custom_frame_and_can_be_disabled():
    native = APP.split('private func showNativeMapModeStartupMessage(', 1)[1].split('private func scheduleAutomaticMapModeStart', 1)[0]
    assert 'HudCommands.pushMessage(position: 0, type: 0, title: "MAP MODE", message: detail)' in native
    assert 'HUD.MapMode.nativeStartupMessageEnabled' in native
    assert 'nativeMapModeMessageStage != stage' in native
    assert 'musicNotification' not in native
    assert 'widgetsMiniState' not in native
    assert 'notificationTimeout' not in native
    assert 'static func pushMessage(' in CMD
    assert 'Toggle("Show startup message on stock HUD"' in UI
    assert '@AppStorage("HUD.MapMode.nativeStartupMessageEnabled")' in UI
    assert 'No message is drawn on the Map Mode screen' in UI


def test_vehicle_obd_ui_simplified_without_removing_widgets_or_underlying_capture():
    assert 'Auto-connect OBD after HUD connects' in VEH
    assert 'Connect via HUD' in VEH and 'Disconnect HUD OBD' in VEH
    assert 'Freeride HUD widgets' in VEH and 'Navigation HUD widgets' in VEH
    assert 'Apply Freeride Widgets' in VEH and 'Apply Navigation Widgets' in VEH
    for removed in ['OBD speed protocol trace', 'HUD OBD diagnostic capture', 'Request latest HUD OBD logs', 'Stop & save raw', 'Returned categories']:
        assert removed not in VEH
    assert 'func requestOBDDiagnosticLogs(' in (ROOT / 'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()


def test_no_regression_in_existing_apple_metadata_and_firmware():
    shortcuts = (ROOT / 'ios/HUDController/Shortcuts/HudShortcuts.swift').read_text()
    assert 'Toggle the saved automatic Map Mode preference using the Action Button or Back Tap.' in shortcuts
    assert 'using the iPhone Action Button' not in shortcuts
    assert 'appVersion=v90.35.3.24.38' in APP
