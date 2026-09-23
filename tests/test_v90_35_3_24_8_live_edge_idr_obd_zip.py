from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
OBD = (ROOT / 'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()
ROUTE = (ROOT / 'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
V827 = ROOT / 'u2w/v8.27_LiveEdgeIDRRelay'
RELAY = (V827 / 'source/u2w_mainvideo_relay.c').read_text()
INSTALL = (V827 / 'source/install_once.sh').read_text()
START = (V827 / 'source/u2wvideo-relay-start.cgi').read_text()
STATUS = (V827 / 'source/u2wvideo-relay-status.cgi').read_text()


def test_v827_is_lightweight_live_edge_next_idr_only():
    assert 'U2WH2645' in RELAY
    assert 'live-edge-initialized-no-history-scan' in RELAY
    assert 'client-bootstrap-next-validated-live-idr' in RELAY
    assert 'source-generation-change-preserve-parser-and-codec-state' in RELAY
    assert 'HEARTBEAT_IDLE_TICKS' in RELAY
    assert 'waiting_slices_since_heartbeat>=30U' in RELAY
    assert 'SO_SNDTIMEO' in RELAY
    assert 'tv.tv_sec=1' in RELAY
    assert 'newest_valid_gop' not in RELAY
    assert 'begin_live_from_cache' not in RELAY
    assert 'cache_write_record_fd' not in RELAY
    assert '/tmp/u2w_mainvideo_validated_gop.cache' not in RELAY


def test_v827_installer_removes_old_cache_without_touching_applecarplay_or_hud_cast():
    assert 'rm -f /tmp/u2w_mainvideo_relay.pid /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new /tmp/u2w_mainvideo_validated_gop.cache' in INSTALL
    for token in ['applecarplay_hook_changed=0', 'route_guidance_changed=0',
                  'now_playing_changed=0', 'hud_cast_relay_changed=0',
                  'persistent_gop_cache=0', 'historical_gop_scan=0']:
        assert token in INSTALL
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'cp "$P/u2whud_cast_relay' not in INSTALL
    assert 'persistent_gop_cache=0' in START
    assert "echo 'gop_cache_file_bytes=0'" in STATUS
    assert 'netstat' not in STATUS


def test_ios_v827_keeps_tcp_during_expected_idr_wait_and_understands_heartbeats():
    assert 'Data("U2WH2645".utf8)' in VIDEO
    assert 'if length == 0' in VIDEO
    assert 'v8.27 relay transport heartbeat' in VIDEO
    assert 'v8.27 LIVE-IDR recovery; TCP PRESERVED' in VIDEO
    assert 'waiting for next live IDR' in VIDEO
    assert 'relayHealthInterval: TimeInterval = self.adapterRelayVersion.contains("v8.27") ? 60.0 : 15.0' in VIDEO
    assert 'source-silence reconnect SUPPRESSED until real TCP failure/EOF or manual request' in VIDEO


def test_physical_hud_viewer_health_fails_safe_without_restarting_mainvideo():
    assert 'hudU2WDisplayHealthTask' in APP
    assert 'hudU2WCurrentSessionWasReady' in APP
    assert 'hudU2WConsecutiveUnhealthySTAStatus >= 2' in APP
    assert 'HUD STA status silent >12s after live session' in APP
    assert 'Physical Map Mode fail-safe → stock dashboard' in APP
    assert 'MainVideo + iPhone JPEG relay intentionally kept alive' in APP
    assert 'viewer recovery #' in APP
    assert 'u2whud-start.cgi' in APP


def test_route_state_zero_transient_lease_covers_observed_six_second_gap():
    assert 'inactiveRouteEndConfirmationInterval: TimeInterval = 12.0' in ROUTE
    assert r'holding active HUD guidance for \(Int(inactiveRouteEndConfirmationInterval))s' in ROUTE


def test_obd_zip_reassembly_preserves_real_chunk_starts_and_reduces_logging_pressure():
    assert 'if data.first == HudProtocol.stx { return false }' in OBD
    assert 'Fresh diagnostic STX replaced incomplete frame' in OBD
    assert 'obdDiagnosticRecentContinuationFragments.removeAll(keepingCapacity: true)' in OBD
    assert 'available == chunkSize' in OBD
    assert 'for i in 0..<allChunks' in OBD
    assert 'archive.count == totalSize' in OBD
    assert 'archive.starts(with: [0x50, 0x4B]) ? "zip" : "bin"' in OBD
    # Diagnostic continuation fragments are consumed before verbose RX logging.
    diagnostic_first = OBD.index('if self.consumeDiagnosticBLEFragment(data) { return }')
    verbose_rx = OBD.index('self.logger.log("RX CHUNK", self.lastRX)', diagnostic_first)
    assert diagnostic_first < verbose_rx
    assert '(chunkIndex + 1) % 25 == 0' in OBD


def test_obd_archive_collection_is_parked_only_and_ui_documents_v248_v827():
    assert 'guard speedEngine.currentSpeedMph <= 1 else' in APP
    assert 'Collecting/reconstructing HUD diagnostic ZIP' in APP
    assert 'Collect/reconstruct HUD OBD ZIP (parked)' in UI
    assert 'v90.35.3.24.8 pairs with U2W v8.27' in UI
    assert '10 fps remains the recommended validation cadence' in UI
