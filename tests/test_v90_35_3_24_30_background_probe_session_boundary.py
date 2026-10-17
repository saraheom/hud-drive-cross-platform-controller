from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VIDEO=(ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
SETTINGS=(ROOT/'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
UI=(ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
CANVAS=(ROOT/'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
SNAP=(ROOT/'ios/HUDController/MapMode/HudMapModeSnapshot.swift').read_text()
APP=(ROOT/'ios/HUDController/App/AppState.swift').read_text()
U2W=ROOT/'u2w/v8.39_SessionBoundaryRecovery_v838Bootstrap'
START=(U2W/'source/u2whud-start.cgi').read_text()
INSTALL=(U2W/'source/install_once.sh').read_text()
RGD=(U2W/'source/u2w_rgd_preload_v839.c').read_text()

def test_background_continuity_is_fixed_to_field_validated_production_mode():
    assert 'backgroundProbeMode' in VIDEO
    assert 'backgroundProbeMode = .keepDecoderBackgroundTask' in SETTINGS
    assert 'Map Mode Background Continuity Probe' not in UI
    assert 'Apply for next Map Mode session' not in UI
    assert 'Keep decoder + BG task' in UI
    assert 'selectMapModeBackgroundProbeMode' not in APP
    assert 'applyMapModeBackgroundProbeModeForNextSession' not in APP
    assert 'setMapModePreventAutoLock' in APP

def test_background_probe_requests_and_reports_hardware_and_has_readonly_rebootstrap_fallback():
    assert 'NSNumber(value: preferHardwareAccelerated)' in VIDEO
    assert 'kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder' in VIDEO
    assert 'VTSessionCopyProperty' in VIDEO
    assert 'restartWorkerWithReadOnlyBootstrap' in VIDEO
    assert 'startupBootstrap: true' in VIDEO
    assert 'suspendDecodePreservingTransport' in VIDEO

def test_eta_lane_arbitration_uses_actual_visibility_and_ampm_is_unicode_safe():
    assert 'laneGuidanceVisible' in SNAP and 'snapshot.laneGuidanceVisible' in CANVAS
    assert 'laneGuidanceVisible: shouldDisplayActiveLanes()' in APP
    assert '\\u{202F}' in CANVAS and '\\u{00A0}' in CANVAS and '.isWhitespace' in CANVAS

def test_v839_fresh_hud_session_restarts_only_custom_helpers():
    assert 'fresh_helpers=YES' in START
    assert 'stop_one ingress' in START and 'stop_one discovery' in START and 'stop_one cast' in START
    assert 'applecarplay_process_control=NEVER' in START
    assert 'mainvideo_process_control=NEVER' in START
    assert 'reused=0 fresh_session=YES' in START

def test_v839_route_guidance_rearms_on_new_wifi_identify_and_install_is_v838_gated():
    assert 'rearm_rgd_for_new_wifi_session' in RGD
    assert 'g_identify_accept_seen || g_sent_5200 || g_got_520x' in RGD
    assert 're-armed Route Guidance negotiation for new CarPlay/iAP2 session' in RGD
    assert '/etc/u2w_v8_38_bootstrap_snapshot.marker' in INSTALL
    assert 'OLD_RGD_SHA1=2dca814e86be234bdbe7c8effdd381b2f16bd0fa' in INSTALL
    assert 'mainvideo_mirror_changed=NO' in INSTALL and 'mainvideo_relay_changed=NO' in INSTALL
