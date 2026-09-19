from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VIDEO=(ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
BT=(ROOT/'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()
CMD=(ROOT/'ios/HUDController/Protocol/HudCommands.swift').read_text()
UI=(ROOT/'ios/HUDController/UI/VehicleView.swift').read_text()
STREAM=(ROOT/'u2w/v8.16_LiveEdgeMainVideo/source/u2w_mainvideo_streamer.c').read_text()

def test_live_edge_streamer_does_not_start_at_zero():
    assert 'newest_gop' in STREAM
    assert 'reopen the pathname' in STREAM
    assert 'byte_zero_replay_on_reconnect=0' in (ROOT/'u2w/v8.16_LiveEdgeMainVideo/source/install_once.sh').read_text()

def test_ios_watchdog_is_less_aggressive_and_tracks_bytes():
    assert 'decoderStaleFrameInterval: TimeInterval = 3.0' in VIDEO
    assert 'sourceStaleInterval: TimeInterval = 15.0' in VIDEO
    assert 'onBytes' in VIDEO
    assert 'receivedBytes' in VIDEO
    assert 'kVTInvalidSessionErr (-12903)' in VIDEO
    assert 'historical GOP replay=0' in VIDEO
    assert 'WAITING_LIVE_IDR' in VIDEO
    assert 'HARD decoder recovery, TCP preserved' in VIDEO

def test_stock_hud_obd_log_protocol_is_exposed():
    assert 'requestOBDDiagnosticLogs' in CMD
    assert 'LOG_CATEGORY_OBD' in CMD
    assert 'command: 5, p1: 1, p2: 0' in CMD
    assert 'CrushLogDiagnosticEventPacket' in BT
    assert 'HUD_Diagnostic_' in BT
    assert 'Request latest HUD OBD logs' in UI
    assert 'Share HUD OBD diagnostic ZIP' in UI
