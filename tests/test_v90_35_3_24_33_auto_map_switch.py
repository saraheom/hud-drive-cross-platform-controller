"""v24.33 regression contracts. These are source-level checks, not iOS device tests."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / "ios/HUDController"
APP = (ROOT / "App/AppState.swift").read_text()
UI = (ROOT / "UI/NavigationHUDPreviewCard.swift").read_text()
ROOTVIEW = (ROOT / "UI/RootView.swift").read_text()
SHORTCUTS = (ROOT / "Shortcuts/HudShortcuts.swift").read_text()
CANVAS = (ROOT / "MapMode/HudMapModeCanvas.swift").read_text()
VIDEO = (ROOT / "MapMode/U2WMainVideoClient.swift").read_text()


def test_auto_preference_survives_disconnect_and_is_separate_from_active_relay():
    assert '"HUD.MapMode.autoEnabled"' in APP
    assert "private(set) var automaticMapModeEnabled" in APP
    assert 'self.hudU2WLiveRelayActive = false' in APP
    disconnected = APP.split('bluetooth.onTransportDisconnected =', 1)[1].split('mapModeCastServer.onEvent', 1)[0]
    assert 'automaticMapModeEnabled = false' not in disconnected
    assert 'scheduleAutomaticMapModeStart(reason: "HUD BLE transport ready")' in APP
    assert 'automaticMapModeAttemptedOnThisConnection' in APP
    assert 'automaticMapModeScheduleGeneration == generation' in APP


def test_switch_sets_preference_without_impersonating_physical_connection():
    assert 'Toggle("Automatic Map Mode"' in UI
    assert 'get: { state.automaticMapModeEnabled }' in UI
    assert 'state.setAutomaticMapModeEnabled($0, reason: "main-tab switch")' in UI
    assert 'state.hudU2WLiveRelayActive' in UI
    assert 'Button("Enable Map Mode")' not in UI


def test_shortcuts_use_real_app_intents_and_shared_saved_state():
    for symbol in ['EnableAutomaticMapModeIntent', 'DisableAutomaticMapModeIntent',
                   'ToggleAutomaticMapModeIntent', 'HUDMapModeShortcutCoordinator']:
        assert symbol in SHORTCUTS
    assert SHORTCUTS.count('static let supportedModes: IntentModes = [.background]') == 3
    assert 'weak var activeState: AppState?' in SHORTCUTS
    assert 'activeState?.setAutomaticMapModeEnabled' in SHORTCUTS
    assert 'state.synchronizeAutomaticMapModePreference' in ROOTVIEW


def test_no_dummy_map_and_eta_is_legible():
    map_block = CANVAS.split('private var mapBlock: some View {', 1)[1].split('private var streetBlock', 1)[0]
    assert 'Color.black' in map_block
    assert 'HudMapModeSchematic(' not in map_block
    eta = CANVAS.split('private var etaBlock: some View {', 1)[1].split('private var timeLeftBlock', 1)[0]
    assert '.foregroundStyle(.white)' in eta
    assert '"MAP ETA"' in APP


def test_cold_start_status_is_rechecked_without_repeat_start_and_no_adapter_reflash():
    snippet = VIDEO.split('func ensureAdapterRelay(reason:', 1)[1].split('private func refreshAdapterRelayStatus', 1)[0]
    assert 'return await refreshAdapterRelayStatus(reason: "cold-start cooldown recheck' in snippet
    assert 'return adapterRelayConfirmedRunning' not in snippet
    assert 'attempt == 1 ? 2 : 3' in VIDEO
    assert 'self.mainVideo.start(reason: "physical Map Mode live source (optional)")' in APP
    assert 'mainVideoDiagnostic?.ensureStarted(reason:' not in APP
    assert 'U2W_MainVideo_Passive_Diagnostic.tar.gz' in APP
