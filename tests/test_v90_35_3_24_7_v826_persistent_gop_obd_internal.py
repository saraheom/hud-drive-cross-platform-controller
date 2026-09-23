from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
V826 = ROOT / 'u2w/v8.26_PersistentGOPBridge'
RELAY = (V826 / 'source/u2w_mainvideo_relay.c').read_text()
INSTALL = (V826 / 'source/install_once.sh').read_text()
UNINSTALL = (V826 / 'source/uninstall_once.sh').read_text()


def test_v826_persists_validated_gop_across_v811_file_rotations():
    assert 'U2WH2644' in RELAY
    assert '/tmp/u2w_mainvideo_validated_gop.cache' in RELAY
    assert 'generation_policy=preserve_decoder_chain_across_v8_11_file_rotation' in INSTALL
    assert 'source-generation-change-preserve-validator-client-and-gop-cache' in RELAY
    generation_block = RELAY.split('source-generation-change-preserve-validator-client-and-gop-cache')[0][-500:]
    assert 'reset_filter(&live_filter)' not in generation_block
    assert 'cache_invalidate' not in generation_block
    assert 'gop_cache_ready=' in RELAY
    assert 'gop_cache_replays=' in RELAY
    assert 'codec_epoch_resets=' in RELAY


def test_v826_cache_is_single_process_wire_framed_and_bounded():
    assert '#define CATCHUP_CAP (48*1024*1024)' in RELAY
    assert 'cache_write_record_fd' in RELAY
    assert 'cache_reset_with_idr' in RELAY
    assert 'cache_append' in RELAY
    assert 'begin_live_from_cache' in RELAY
    assert 'CACHE_REPLAY_PACE_EVERY_SLICES' in RELAY
    assert 'gop-cache-overflow-wait-next-idr' in RELAY
    assert 'killall u2w_mainvideo_cache' in INSTALL  # retire old separate cache daemon if present
    assert 'u2w_mainvideo_cache"' not in INSTALL


def test_v826_scopes_firmware_change_to_mainvideo_relay_and_rolls_back_to_v825():
    for token in ['applecarplay_hook_changed=0', 'route_guidance_changed=0',
                  'now_playing_changed=0', 'hud_cast_relay_changed=0']:
        assert token in INSTALL
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'u2w_mainvideo_relay_v825' in UNINSTALL
    assert 'u2w_v8_25_validated_gop_relay.marker' in UNINSTALL


def test_ios_accepts_v826_and_holds_waiting_tcp_while_adapter_source_advances():
    assert 'Data("U2WH2644".utf8)' in VIDEO
    assert 'relayVersion.contains("v8.26")' in VIDEO
    assert 'gop_cache_ready' in VIDEO
    assert 'adapterRelayLastSourceProgressAt' in VIDEO
    assert 'WAITING bootstrap held on same TCP' in VIDEO
    assert 'source-silence reconnect SUPPRESSED until real TCP failure/EOF or manual request' in VIDEO


def test_ios_startup_watchdog_has_bootstrap_hysteresis():
    assert 'startupDecoderGraceFrameCount = 10' in VIDEO
    assert 'startupDecoderGraceInterval: TimeInterval = 8.0' in VIDEO
    assert 'let decoderIsEstablished = self.frameCount >=' in VIDEO
    assert 'if decoderIsEstablished, bytesAreFresh' in VIDEO


def test_obd_v4_targets_hud_internal_logs_without_second_obd_connection():
    assert 'startHUDOBDInternalSpeedProbeV4' in APP
    assert 'for attempt in 1...18' in APP
    assert 'HudOBDItem.drivingVelocity.rawValue' in APP
    assert 'requestOBDDiagnosticLogs(maxLastFilesCount: 5)' in APP
    assert 'LOG_CATEGORY_OBD' in APP
    assert 'no second OBD connection' in APP
    assert 'Run 90 s HUD-internal OBD probe v4' in UI
    assert 'Collect/reconstruct HUD OBD ZIP (parked)' in UI
    assert 'Share HUD OBD diagnostic ZIP' in UI


def test_ui_documents_v247_v826_pair_and_10fps_validation():
    assert 'v90.35.3.24.8 pairs with U2W v8.27' in UI
    assert '10 fps remains the recommended validation cadence' in UI
