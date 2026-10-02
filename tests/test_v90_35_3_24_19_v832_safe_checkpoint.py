from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VIDEO=(ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
SAN=(ROOT/'ios/HUDController/MapMode/H264MainVideoSanitizer.swift').read_text()
APP=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
RELAY=(ROOT/'u2w/v8.32_SafeBoundedCheckpoint/source/u2w_mainvideo_relay.c').read_text()
INSTALL=(ROOT/'u2w/v8.32_SafeBoundedCheckpoint/source/install_once.sh').read_text()
START=(ROOT/'u2w/v8.32_SafeBoundedCheckpoint/source/u2wvideo-relay-start.cgi').read_text()

def test_app_understands_v832_and_uses_one_bounded_checkpoint_rebootstrap():
    assert 'Data("U2WH2649".utf8)' in VIDEO
    assert 'boundedCheckpointRecovery = true' in VIDEO
    assert 'v8.32 safe-checkpoint recovery' in VIDEO
    assert 'checkpoint already attempted in this recovery episode; no reconnect loop' in VIDEO
    assert 'v8.32 checkpoint already attempted in this recovery episode; no reconnect loop' in VIDEO

def test_iphone_rejects_false_type5_idr_shape_seen_oct1():
    assert 'let sliceType: UInt32' in SAN
    assert 'normalizedSliceType == 2 || normalizedSliceType == 4' in SAN
    assert 'info.frameNum == 0' in SAN

def test_physical_map_mode_stays_alive_while_mainvideo_recovers():
    block=APP.split('private func startHUDU2WDisplayHealthMonitor()',1)[1].split('private func failSafeHUDU2WDisplayToStock',1)[0]
    assert 'KEEPING physical mode 6 + JPEG relay active' in block
    assert 'fallback canvas' in block
    assert 'stopHUDU2WSTAHomeProbe()' not in block
    assert 'HudCommands.kivicMode(4)' not in block

def test_v832_is_strict_bounded_and_current_generation_only():
    assert '#define CHECKPOINT_CAP 1572864U' in RELAY
    assert 'U2WH2649' in RELAY
    assert 'strict_idr' in RELAY
    assert 'frame_num_discontinuities' in RELAY
    assert 'checkpoint-hard-cap-expired-wait-next-idr' in RELAY
    assert 'startup-forward-scan-current-mirror-only' in RELAY
    assert 'source-generation-change-preserve-validator-check-continuity' in RELAY

def test_v832_preserves_v831_process_safety_boundary():
    assert 'EXPECTED_SELECTOR_SHA1=7ab8e227893277c9c1135a398e24e41c8f84d4df' in INSTALL
    assert 'V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6' in INSTALL
    assert 'source_selector_changed=0' in INSTALL
    assert 'applecarplay_restart_policy=NEVER' in INSTALL
    assert 'relay_autostart=0' in INSTALL
    assert 'historical_generation_scan=0' in INSTALL
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'kill AppleCarPlay' not in INSTALL
    assert 'source_reacquire=NEVER' in START
