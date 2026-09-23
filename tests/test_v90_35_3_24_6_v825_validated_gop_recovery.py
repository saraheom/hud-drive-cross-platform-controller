from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
AMBIENT = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
V825 = ROOT / 'u2w/v8.25_ValidatedGOPRecovery'
RELAY = (V825 / 'source/u2w_mainvideo_relay.c').read_text()
INSTALL = (V825 / 'source/install_once.sh').read_text()
STATUS = (V825 / 'source/u2wvideo-relay-status.cgi').read_text()


def test_v825_uses_newest_validated_800x480_file_gop_with_bounded_catchup():
    assert '#define EXPECT_WIDTH 800' in RELAY
    assert '#define EXPECT_HEIGHT 480' in RELAY
    assert '#define CATCHUP_CAP (48*1024*1024)' in RELAY
    assert '#define CATCHUP_FRAME_PACE_MS 4' in RELAY
    assert 'CATCHING_UP_GOP' in RELAY
    assert 'catchup_frames=' in RELAY
    assert 'newest_valid_gop' in RELAY
    assert 'file_gop_scan_attempts' in RELAY
    assert 'file_gop_bootstraps' in RELAY
    assert 'generation_reseeds' in RELAY
    assert 'validated-gop-catchup-cap-exceeded-wait-live-idr' in RELAY
    assert "{'U','2','W','H','2','6','4','3'}" in RELAY


def test_v825_validates_h264_before_forwarding_and_falls_back_to_live_idr():
    for token in ['parse_sps', 'parse_pps', 'parse_slice_info', 'accept_slice', 'begin_live_at_idr']:
        assert token in RELAY
    assert 'client-bootstrap-fresh-validated-live-idr' in RELAY
    assert 'rejected_nals=' in RELAY
    assert 'pre_idr_slices_dropped=' in RELAY


def test_v825_install_is_scoped_to_mainvideo_relay_only():
    assert '/usr/lib/u2wvideo/u2w_mainvideo_relay' in INSTALL or 'LIB=/usr/lib/u2wvideo' in INSTALL
    assert 'applecarplay_hook_changed=0' in INSTALL
    assert 'route_guidance_changed=0' in INSTALL
    assert 'now_playing_changed=0' in INSTALL
    assert 'hud_cast_relay_changed=0' in INSTALL
    assert 'cp "$P/u2whud_cast_relay' not in INSTALL
    assert 'killall AppleCarPlay' not in INSTALL
    assert 'u2w_v8_25_validated_gop_relay.marker' in INSTALL


def test_ios_accepts_v824_or_v825_and_surfaces_v825_diagnostics():
    assert 'relayVersion.contains("v8.24") || relayVersion.contains("v8.25") || relayVersion.contains("v8.26")' in VIDEO
    assert 'U2WH2642' in VIDEO and 'U2WH2643' in VIDEO and 'U2WH2644' in VIDEO
    for token in ['file_gop_scan_attempts', 'file_gop_scan_misses', 'file_gop_cap_rejects',
                  'file_gop_bootstraps', 'generation_reseeds', 'file_gop_catchup_cap',
                  'catchup_active', 'catchup_bytes', 'catchup_frames', 'catchup_target_bytes']:
        assert token in VIDEO
    assert 'bounded decoder recovery persistent-GOP reseed' in VIDEO
    assert 'TCP PRESERVED' in VIDEO


def test_ui_keeps_10fps_validation_guidance_and_documents_v826_successor():
    assert 'pairs with U2W v8.27' in UI
    assert '10 fps remains the recommended validation cadence' in UI


def test_ambient_has_no_new_246_door_reassert_feature():
    # The 24.6 scope deliberately excludes a new post-transition Door brightness
    # reconciliation/reassert experiment. Existing ambient code remains the 24.5 baseline.
    assert 'v90.35.3.24.6' not in AMBIENT
    assert 'Center-only DAY guard armed' in AMBIENT
