from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
UI = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
MAINT = (ROOT / "ios/HUDController/Firmware/HudMaintenanceManager.swift").read_text()
ADB = (ROOT / "ios/HUDController/Firmware/HUDADBClient.swift").read_text()
BOOT = (ROOT / "ios/HUDController/Firmware/BootAnimationArchive.swift").read_text()


def test_boot_override_is_reversible_and_never_writes_system_partition():
    assert 'remoteOverride = "/data/local/bootanimation/bootanimation.zip"' in MAINT
    assert 'remotePending = "/data/local/bootanimation/bootanimation.zip.pending"' in MAINT
    assert 'mv \\(Self.remotePending) \\(Self.remoteOverride)' in MAINT
    assert 'rm -f \\(Self.remoteOverride) \\(Self.remotePending)' in MAINT
    assert 'system/media/bootanimation.zip' in UI  # user-facing untouched-stock explanation
    for forbidden in ('mount -o rw', 'remount', 'rm -f /system/', 'mv /system/', 'cp /system/'):
        assert forbidden not in MAINT.lower()
    assert 'HudCommands.softwareUpdate' not in APP


def test_install_uses_pending_upload_and_complete_readback_hash_before_commit():
    upload = MAINT.index('adb.push(localURL: prepared.url, remotePath: Self.remotePending)')
    readback = MAINT.index('adb.hashRemoteFile(Self.remotePending)', upload)
    commit = MAINT.index('mv \\(Self.remotePending) \\(Self.remoteOverride)', readback)
    final_hash = MAINT.index('adb.hashRemoteFile(Self.remoteOverride)', commit)
    assert upload < readback < commit < final_hash
    assert 'remote.sha256.caseInsensitiveCompare(prepared.sha256)' in MAINT
    assert 'remote.byteCount == prepared.byteCount' in MAINT
    assert '[ -d \\(Self.remoteDirectory) ] && [ -w \\(Self.remoteDirectory) ]' in MAINT


def test_adb_client_is_minimal_insecure_hud_transport_with_sync_send_and_recv():
    assert 'Data("host::\\0".utf8)' in ADB
    assert 'case authRequired' in ADB
    assert 'if packet.command == Self.auth' in ADB
    assert 'openService("sync:")' in ADB
    for token in ('"SEND"', '"DATA"', '"DONE"', '"RECV"', '"FAIL"'):
        assert token in ADB
    assert 'RSA' not in ADB
    assert '192.168.43.1' in ADB


def test_video_conversion_matches_stock_hud_native_bootanimation_shape():
    assert 'static let width = 480' in BOOT
    assert 'static let height = 240' in BOOT
    assert 'static let fps = 24' in BOOT
    assert 'static let maximumDuration = 12.0' in BOOT
    assert '480 240 24\\np 1 0 part0\\np 0 0 part1' in BOOT
    assert 'part0/frame_%03d.png' in BOOT
    assert 'part1/frame_000.png' in BOOT
    assert 'format.scale = 1.0' in BOOT
    assert 'pngDimensions' in BOOT
    assert 'archiveBytes <= maximumArchiveBytes' in BOOT
    # ZIP method 0 / STORE is required by the Android bootanimation path.
    assert 'header.appendLE16(0) // STORE' in BOOT


def test_maintenance_ui_requires_explicit_confirmations_for_write_restore_and_reboot():
    for token in (
        'Start Firmware Maintenance',
        'Select Video or bootanimation.zip',
        'Install Custom Boot Animation',
        'Restore Stock',
        'Reboot HUD to Test Animation',
        'Install custom boot animation?',
        'Restore stock boot animation?',
        'Reboot HUD now?',
    ):
        assert token in UI
    assert 'Pin AP + Return HUD Mode 4' not in UI
    assert 'hudHotspotBaseband(is5G: true, forceEnable: true)' not in APP


def test_first_boot_animation_build_keeps_existing_signing_and_uses_manual_wifi_join():
    assert 'NetworkExtension' not in MAINT
    assert 'NEHotspotConfiguration' not in MAINT
    assert '87654321' in UI
    maintenance = APP[APP.index('func startFirmwareMaintenance'):APP.index('func reconnectFirmwareMaintenanceADB')]
    assert 'enableHUDWiFiExposure()' in maintenance
    assert 'routeGuidance.stop' in maintenance
    assert 'nowPlaying.stop' in maintenance
    assert 'iPhone Wi-Fi Settings' in maintenance
