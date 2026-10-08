from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
V834 = ROOT / "u2w" / "v8.34_HardBoundedMirrorRawRelay"
SRC = (V834 / "source" / "libu2w_mainvideo_hardbounded.c").read_text()
INSTALL = (V834 / "source" / "install_once.sh").read_text()
STATUS = (V834 / "source" / "u2wvideo-relay-status.cgi").read_text()
BT = (ROOT / "ios/HUDController/Bluetooth/HudBluetoothManager.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()


def test_v834_rotates_at_hard_8mib_write_boundary_without_sps_dependency():
    compact = "".join(SRC.split())
    assert "#defineROTATE_AT(8U*1024U*1024U)" in compact
    assert "g_file_bytes>0&&(g_file_bytes>=ROTATE_AT||n>ROTATE_AT-g_file_bytes)" in compact
    assert "if(c7&&g_file_bytes>=ROTATE_AT)" not in compact
    assert "rotate_live_atomic(p,n,n)" in compact
    assert "hard-8MiB-applecarplay-write-boundary-atomic-inode-swap" in SRC


def test_v834_passively_unlatches_only_when_selected_fd_closes():
    assert "int close(int fd)" in SRC
    assert "was_main=(fd==g_main_fd)" in SRC.replace(" ", "")
    assert "g_source_unlatches++" in SRC
    assert "source_selection=passive-first-sps-fd-with-close-unlatch" in SRC
    lower = INSTALL.lower()
    assert "kill applecarplay" not in lower
    assert "killall applecarplay" not in lower
    assert "pkill applecarplay" not in lower
    assert "applecarplay_signal_policy=never" in lower
    assert "applecarplay_restart_policy=never" in lower


def test_v834_keeps_exact_v831_raw_relay_and_adds_tmpfs_telemetry():
    relay = V834 / "source" / "u2w_mainvideo_relay"
    assert hashlib.sha256(relay.read_bytes()).hexdigest() == "1c19377dbc9bdc4256dc109053824704a966448ffa9ae8d3472cf76c895e4a90"
    assert "tmpfs_free_kb" in STATUS
    assert "mirror_resource_guard_trips" in STATUS
    assert "resource_guard_trips" in SRC
    assert "fail-closed-mainvideo-only" in SRC
    assert "mirror_hard_cap_rotations" in STATUS
    assert "mirror_source_unlatches" in STATUS
    assert "v8.34-hard-bounded-mirror-v831-raw-tcp-15332" in VIDEO


def test_obd_flight_recorder_is_automatic_passive_and_file_backed():
    assert 'obdDriveRecorderStatus = "Armed — starts automatically with HUD OBD"' in BT
    assert 'startOBDDriveFlightRecorder(reason: "HUD OBD connected' in BT
    assert 'recordOBDDriveRX(data)' in BT
    assert 'recordOBDDriveGPS()' in BT
    assert 'label.localizedCaseInsensitiveContains("OBD")' in BT
    assert 'drive_raw_ble.bin' in BT
    assert 'drive_rx_notifications.csv' in BT
    assert 'gps_reference.csv' in BT
    assert 'obd_state_timeline.csv' in BT
    assert 'for attempt in 1...18' in APP  # legacy v4 retained for compatibility only
    assert 'Collect OBD Drive Diagnostic ZIP (parked)' not in UI
    assert 'Collect Live Map Diagnostic ZIP (parked)' in UI
    assert 'Collect Live Map Diagnostic ZIP (parked)' in UI


def test_parked_obd_bundle_keeps_stock_transfer_separate_and_times_out_safely():
    assert 'requestOBDDiagnosticLogs(maxLastFilesCount: 5)' in APP
    assert 'Date().addingTimeInterval(45.0)' in APP
    assert 'stock_hud_log_transfer' in BT
    assert 'stock_hud_log_transfer_raw.bin' in BT
    assert 'LOG_CATEGORY_CRUSH' in BT
    assert 'HUD_OBD_DriveDiagnostic_v90.35.3.24.28_' in BT


def test_obd_flight_recorder_survives_transient_hud_ble_disconnect():
    assert 'recordOBDDriveEvent("hud_ble_disconnected"' in BT
    assert 'stopOBDDriveFlightRecorder(reason: "HUD BLE disconnected' not in BT
