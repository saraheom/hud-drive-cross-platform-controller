"""Source regression guards for v90.35.3.24.36 BLE recovery + layout protection.

These guard structural safety invariants; real CoreBluetooth callbacks and
native firmware messages still require iOS CI and a parked physical test.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECT_ELM = (ROOT / "ios/HUDController/Bluetooth/DirectELM327Manager.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
MODEL = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
VIEW = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()


def test_obd_recovery_has_watchdog_and_bounded_scans():
    assert 'private func ensureProductionRecoveryLoop(reason: String)' in DIRECT_ELM
    assert 'productionRecoveryAttempts % 2 == 1' in DIRECT_ELM
    assert 'beginScan(duration: 7, productionAutoConnect: true)' in DIRECT_ELM
    assert 'while !Task.isCancelled, self.mapModeOwnershipRequested,' in DIRECT_ELM
    assert 'self.ownershipGeneration == generation' in DIRECT_ELM


def test_obd_recovery_detects_stale_speed_and_gatt():
    assert 'Date().timeIntervalSince(since) > 8' in DIRECT_ELM
    assert 'Date().timeIntervalSince(start) > 15' in DIRECT_ELM
    assert 'speed responses stale' in DIRECT_ELM
    assert 'productionReconnectDisconnectPending = true' in DIRECT_ELM


def test_obd_generation_and_cancel_guards():
    assert 'productionRecoveryTask?.cancel(); productionRecoveryTask = nil' in DIRECT_ELM
    assert 'ownershipGeneration &+= 1 // invalidate every in-flight production connect callback' in DIRECT_ELM
    assert 'let staleProductionConnect = timedOut ||' in DIRECT_ELM
    assert 'productionPollingGeneration == pollingGeneration' in DIRECT_ELM
    assert 'productionPollingGeneration &+= 1' in DIRECT_ELM
    assert 'releaseMapModeOwnershipAndWait(timeout:' in DIRECT_ELM


def test_raw_obd_first_gps_only_when_stale():
    assert 'let speed = directELM.freshSpeedMph() ?? gpsSpeed' in APP
    assert 'Data([0x' not in DIRECT_ELM or '"010D\\r"' in DIRECT_ELM
    assert 'Map Mode direct OBD polling START rate=5Hz command=010D only' in DIRECT_ELM
    assert 'directELM.speedSourceSummary' in APP


def test_preset_reset_undo_persistent_and_local_to_slot():
    assert 'HUD.MapMode.Designer.presetUndo.v1.\\(index)' in MODEL
    assert 'saveBeforeReset()' in MODEL
    assert 'func undoLastReset()' in MODEL
    assert 'defaults.removeObject(forKey: Self.resetUndoKey(activePresetIndex))' in MODEL
    assert 'resetUndoAvailable = loadResetUndo(index) != nil' in MODEL
    assert 'saveCurrentPreset()' in MODEL


def test_destructive_buttons_use_confirmation():
    assert '.confirmationDialog(' in VIEW
    assert 'pendingDesignerReset = .selected' in VIEW
    assert 'pendingDesignerReset = .all' in VIEW
    assert 'pendingDesignerReset = .imported' in VIEW
    assert 'role: .destructive' in VIEW
    assert 'state.mapModeSettings.undoLastReset()' in VIEW


def test_native_message_remains_stock_only_and_has_parked_test():
    assert 'testNativeMapModeStartupMessage()' in APP
    assert '"Parked stock HUD INFO display test"' in APP
    assert 'state.testNativeMapModeStartupMessage()' not in VIEW
    assert '.disabled(state.bluetooth.state != .connected || state.hudU2WLiveRelayActive)' not in VIEW
    assert '"Initializing... (test)"' in APP
