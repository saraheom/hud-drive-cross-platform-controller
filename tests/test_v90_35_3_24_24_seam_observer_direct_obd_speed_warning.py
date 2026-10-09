from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
ELM = (ROOT / "ios/HUDController/Bluetooth/DirectELM327Manager.swift").read_text()
OBD = (ROOT / "ios/HUDController/Vehicle/HudOBDController.swift").read_text()
SETTINGS = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
CANVAS = (ROOT / "ios/HUDController/MapMode/HudMapModeCanvas.swift").read_text()
NAV26 = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
CARD = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
V836 = ROOT / "u2w/v8.36_SeamObserver_v835Keyframe_v834Mirror"
OBSERVER = (V836 / "source/u2w_generation_seam_observer.sh").read_text()
INSTALL = (V836 / "source/install_once.sh").read_text()
STATUS = (V836 / "source/u2wvideo-relay-status.cgi").read_text()


def test_current_release_and_passive_seam_snapshot_collection():
    assert 'appVersion=v90.35.3.24.29' in APP
    assert 'u2wvideo-seam-log.cgi' in APP
    assert 'v8.37 Forensic Seam Capture' in APP
    assert 'v836_marker' in VIDEO
    assert 'seam_event_count' in VIDEO
    assert 'generation_seam' in VIDEO
    assert 'deferred_unverified_stream_ipc' in VIDEO


def test_v836_is_sidecar_only_and_preserves_field_proven_payloads():
    assert (V836 / 'U2W_Update_v8.36_PassiveSeamObserver_v835.img').exists()
    assert (V836 / 'U2W_Update_v8.36_SAFE_ROLLBACK_v8.35.img').exists()
    assert 'b982322ee65fd45405ab40f98512dbd76450976b' in INSTALL
    assert 'b3964792342f9bc5ad22eaeb70eaf84ec04562f6' in INSTALL
    assert 'mirror_payload_changed=NO' in STATUS
    assert 'raw_relay_payload_changed=NO' in STATUS
    assert 'never opens TCP/15332' in OBSERVER
    assert 'never writes the H264 mirror' in OBSERVER
    assert 'old_tail256_sha1' in OBSERVER
    assert 'new_head256_sha1' in OBSERVER
    assert 'relay_pos=' in OBSERVER
    assert 'relay_inode=' in OBSERVER
    assert 'relay_size=' in OBSERVER
    assert '/proc/net/unix' in OBSERVER


def test_map_mode_single_owner_direct_obd_and_speed_polling():
    assert 'suspendForDirectELMOwnership' in OBD
    assert 'resumeAfterDirectELMOwnership' in OBD
    assert 'directELMOwnershipSuspended' in OBD
    assert 'claimForMapMode' in ELM
    assert 'releaseMapModeOwnership' in ELM
    assert 'Map Mode direct OBD polling START rate=5Hz command=010D only' in ELM
    assert 'milliseconds(200)' in ELM
    assert '010D\\r' in ELM
    assert 'ATZ' in ELM and 'ATSP' in ELM  # explicit negative-safety logging/comments remain
    assert 'let speed = directELM.freshSpeedMph() ?? gpsSpeed' in APP


def test_speed_warning_is_independently_customizable_and_separate_main_tab_card():
    for token in [
        'speedWarningEnabled',
        'speedWarningNumberColorEnabled',
        'speedWarningBackgroundEnabled',
        'speedWarningNumberRed',
        'speedWarningBackgroundRed',
        'speedWarningBackgroundOpacity',
    ]:
        assert token in SETTINGS
    assert 'speedWarningActive' in CANVAS
    assert 'MapModeSpeedWarningCard(state: state)' in NAV26
    assert NAV26.index('NavigationHUDPreviewCard(state: state)') < NAV26.index('MapModeSpeedWarningCard(state: state)')
    assert 'struct MapModeSpeedWarningCard' in CARD
    assert 'Enable overspeed warning' in CARD
    assert 'Change speed number color' in CARD
    assert 'Highlight speed background' in CARD
    assert 'Number warning color' in CARD
    assert 'Background warning color' in CARD
