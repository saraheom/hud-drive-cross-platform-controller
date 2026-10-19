"""v24.34 adapter Wi-Fi credential synchronization and auto retry guards."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
SHORTCUTS = (ROOT / "ios/HUDController/Shortcuts/HudShortcuts.swift").read_text()


def test_shared_default_is_applied_to_automatic_start_not_only_settings_view():
    assert 'static let defaultSSID = "NISSAN68"' in APP
    assert '(defaults.string(forKey: ssidKey) ?? defaultSSID)' in APP
    auto = APP.split('private func scheduleAutomaticMapModeStart(reason:', 1)[1].split('func startHUDU2WSTAHomeProbe', 1)[0]
    assert 'HUDU2WAdapterWiFiCredentials.current()' in auto
    assert 'UserDefaults.standard.string(forKey: "HUD.U2WHomeProbe.ssid") ?? ""' not in auto
    assert 'HUDU2WAdapterWiFiCredentials.defaultSSID' in UI


def test_no_silent_password_default_or_password_in_logs():
    assert 'let password = defaults.string(forKey: passwordKey) ?? ""' in APP
    assert 'if credentials.password.isEmpty { return "password" }' in APP
    assert r'missing adapter Wi-Fi \(missing)' in APP
    assert 'password_present=1' in APP
    assert 'logger.log("MAP AUTO", "adapter Wi-Fi settings saved; password=' not in APP


def test_explicit_save_retries_while_preserving_desired_mode():
    assert 'Button("Save adapter Wi-Fi & retry Map Mode")' in UI
    assert 'state.saveMapModeAdapterWiFiCredentials(ssid: u2wSSID, password: u2wPassword)' in UI
    assert 'onChange(of: editingAdapterWiFiField)' in UI
    method = APP.split('func saveMapModeAdapterWiFiCredentials', 1)[1].split('private func scheduleAutomaticMapModeStart', 1)[0]
    assert 'HUDU2WAdapterWiFiCredentials.save' in method
    assert 'automaticMapModeStartTask?.cancel()' in method
    assert 'automaticMapModeAttemptedOnThisConnection = false' in method
    assert 'scheduleAutomaticMapModeStart(reason: "adapter Wi-Fi credentials saved")' in method
    assert 'automaticMapModeEnabled = false' not in method
    assert 'guard automaticMapModeEnabled, !hudU2WLiveRelayActive, !mapModeActive else' in method


def test_apple_metadata_fix_is_inherited():
    assert 'Toggle the saved automatic Map Mode preference using the Action Button or Back Tap.' in SHORTCUTS
    assert 'Toggle the saved automatic Map Mode preference using the iPhone' not in SHORTCUTS
    assert SHORTCUTS.count('static let supportedModes: IntentModes = [.background]') == 3
