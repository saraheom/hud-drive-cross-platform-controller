from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
CANVAS = (ROOT/'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
SETTINGS = (ROOT/'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
SNAPSHOT = (ROOT/'ios/HUDController/MapMode/HudMapModeSnapshot.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
AMBIENT = (ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
RELAY = (ROOT/'u2w/v8.23_LiveIDRRelay/source/u2w_mainvideo_relay.c').read_text()
INSTALL = (ROOT/'u2w/v8.23_LiveIDRRelay/source/install_once.sh').read_text()


def test_v823_waits_for_fresh_live_idr_without_history_burst():
    assert 'U2WH2642' in RELAY and 'U2WH2643' in VIDEO
    assert 'NO cached GOP replay' in RELAY
    assert 'client-connected-waiting-live-idr' in RELAY
    assert 'client-live-bootstrap-sps-pps-idr' in RELAY
    assert 'gop_buf' not in RELAY
    assert 'source-generation-change-parser-continuity-preserved' in RELAY
    generation_block = RELAY.split('if(!same_generation(fd,pos,tail_len))',1)[1].split('else sc3',1)[0]
    assert 'parse_len=0' not in generation_block
    assert 'bounded recent-IDR bootstrap enabled' in VIDEO
    assert 'WAITING_LIVE_IDR' in VIDEO
    assert 'receiveExactly' in VIDEO


def test_tcp_is_not_opened_until_relay_is_confirmed_and_waiting_recovers():
    assert 'relay confirmed RUNNING before TCP open' in VIDEO
    assert 'TCP intentionally NOT opened' in VIDEO
    assert 'TCP WAITING deadline expired' in VIDEO
    assert '4s retry deadline armed' in VIDEO
    assert 'recentAnchorRecoveryUsed' in VIDEO and 'WAITING_FRESH_IDR' in VIDEO


def test_parked_preflight_and_diagnostic_chain_are_visible():
    for token in ['MAINVIDEO PREFLIGHT', 'preflightSummary', 'Last map frame', 'Parked MainVideo preflight']:
        assert token in VIDEO + UI
    assert 'LIVE • 20s continuity verified' in VIDEO
    assert 'source_generation_changes' in VIDEO
    assert 'pre_idr_slices_dropped' in VIDEO
    assert 'MAP RENDER HEARTBEAT' in (ROOT/'ios/HUDController/App/AppState.swift').read_text()


def test_lane_head_and_body_length_are_independent_persisted_controls():
    assert 'laneArrowHeadScale' in SETTINGS and 'laneArrowBodyLength' in SETTINGS
    assert 'Lane arrow head size' in UI
    assert 'Lane arrow body length' in UI
    assert 'headScale: CGFloat(settings.laneArrowHeadScale)' in CANVAS
    assert 'bodyLength: CGFloat(settings.laneArrowBodyLength)' in CANVAS
    assert 'let bottom = h * (0.30 + 0.52 * body)' in CANVAS
    assert 'headHalfW = max(1.7, w * 0.17) * head' in CANVAS


def test_customization_has_always_populated_demo_but_live_preview_stays_live():
    assert 'static let customizationDemo' in SNAPSHOT
    assert 'hasLiveRoute: true' in SNAPSHOT.split('static let customizationDemo',1)[1].split('static let previewFallback',1)[0]
    assert 'snapshot: .customizationDemo' in UI
    # The top preview still uses actual live state, intentionally independent of demo.
    assert 'snapshot: state.mapModePreviewSnapshot' in UI
    assert 'Demo • not live HUD output' in UI


def test_center_transport_disconnect_latches_night_until_absence_is_confirmed():
    disconnect = AMBIENT.split('didDisconnectPeripheral peripheral: CBPeripheral',1)[1].split('// MARK: - CBPeripheralDelegate',1)[0]
    assert 'self.markAbsent(reason: "persistent BLE disconnect")' not in disconnect
    assert 'preserving NIGHT briefly' in disconnect
    assert 'centerTransportUnknownSince' in AMBIENT
    assert 'Center-only DAY guard armed' in AMBIENT
    assert 'Dashboard not required' in AMBIENT
    assert 'preserving NIGHT' in AMBIENT
    assert 'doorTargetBrightness(night: headlightPowerSessionActive)' in AMBIENT


def test_v823_restores_known_good_hud_cast_and_does_not_touch_applecarplay():
    assert 'u2whud_cast_relay_v8151' in INSTALL
    assert 'hud_cast_relay=v8.15.1_restored' in INSTALL
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'pkill AppleCarPlay' not in INSTALL
    assert 'LD_PRELOAD' not in INSTALL


def test_decoder_rebuild_is_deferred_until_a_future_idr_and_logged():
    assert 'rebuildAtNextIDR' in VIDEO
    assert 'Decoder rebuild ARMED' in VIDEO
    assert 'existing session preserved until future IDR' in VIDEO
    assert 'Fresh IDR arrived with rebuild armed; atomically rebuilding decoder now' in VIDEO
    error_block = VIDEO.split('if decodeStatus != noErr {', 1)[1].split('} else {', 1)[0]
    assert 'promoteValidParameterSetPairIfPossible()' not in error_block
    assert 'decoderSummary' in VIDEO
    assert 'VideoToolbox decoder' in UI
