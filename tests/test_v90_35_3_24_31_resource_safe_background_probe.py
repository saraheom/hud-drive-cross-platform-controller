from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
CUR = (ROOT/'u2w/v8.40_ResourceSafeBootstrap_v839Session/source/u2wvideo-bootstrap-current.cgi').read_text()
PREV = (ROOT/'u2w/v8.40_ResourceSafeBootstrap_v839Session/source/u2wvideo-bootstrap-previous.cgi').read_text()
RGD = (ROOT/'u2w/v8.40_ResourceSafeBootstrap_v839Session/source/u2w_rgd_preload_v840.c').read_text()
INSTALL = (ROOT/'u2w/v8.40_ResourceSafeBootstrap_v839Session/source/install_once.sh').read_text()

def test_v840_bootstrap_has_no_per_request_h264_temp_copy():
    assert 'zero-copy-pinned-inode' in CUR
    assert 'zero-copy-pinned-inode' in PREV
    assert 'cat "$LIVE" > "$TMP"' not in CUR
    assert 'u2w_v838_bootstrap_current_$$.h264' not in CUR
    assert 'u2w_v838_bootstrap_previous_$$.h264' not in PREV
    assert 'head -c "$N" /proc/$$/fd/8' in CUR
    assert 'head -c "$N" /proc/$$/fd/8' in PREV

def test_bootstrap_is_single_flight_and_cooldown_gated():
    assert 'startupSnapshotFetchTask' in VIDEO
    assert 'single-flight JOIN' in VIDEO
    assert 'readOnlyRebootstrapCooldown' in VIDEO
    assert 'readonly_rebootstrap_suppressed' in VIDEO

def test_resource_safe_bootstrap_is_used_by_fixed_production_background_mode():
    assert 'selectMapModeBackgroundProbeMode' not in APP
    assert 'applyMapModeBackgroundProbeModeForNextSession' not in APP
    assert 'Keep decoder + BG task' not in UI
    assert 'lock-time -12903 detected' in VIDEO
    assert 'restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")' in VIDEO

def test_rgd_publish_is_fail_closed_and_diagnostics_bounded():
    assert 'publish_atomic_full' in RGD
    assert 'if(!write_full_fd(fd,buf,n))' in RGD
    assert 'unlink(tmp)' in RGD
    assert 'resource_live_json_failures' in RGD
    assert '512L*1024L' in RGD
    assert 'legacy_bootstrap_temp_cleanup=YES' in INSTALL

def test_release_pairs_v840_without_changing_proven_mirror_relay():
    assert 'appVersion=v90.35.3.24.' in APP
    assert 'paired_u2w=v8.40 Resource-Safe Bootstrap + v8.39 Session Boundary Recovery' in APP
    assert 'unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay' in VIDEO
