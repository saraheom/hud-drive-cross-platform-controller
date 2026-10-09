from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
SETTINGS = (ROOT / 'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
CANVAS = (ROOT / 'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
V838 = ROOT / 'u2w/v8.38_ReadOnlyBootstrapSnapshot_v837Forensic_v834Mirror/source'


def test_v2429_pairs_with_read_only_v838_and_preserves_transport_stack():
    assert 'appVersion=v90.35.3.24.29' in APP
    assert 'v8.38 Read-Only Startup Bootstrap' in APP
    assert 'v90.35.3.24.29 MainVideo client for U2W v8.38 read-only startup bootstrap' in VIDEO
    install = (V838 / 'install_once.sh').read_text()
    assert 'V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b' in install
    assert 'V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6' in install
    assert 'mirror_payload_changed=0' in install
    assert 'raw_relay_payload_changed=0' in install
    assert 'snapshot_applecarplay_process_control=NEVER' in install
    assert 'snapshot_observer_autostart=YES_READ_ONLY_ONLY' in install
    assert '/etc/init.d/S98u2w_v838_bootstrap_observer' in install


def test_startup_bootstrap_attaches_live_tcp_first_then_overlap_joins_snapshots():
    current = VIDEO.index('("current-generation", bootstrapCurrentEndpoint)')
    previous = VIDEO.index('("previous-generation", bootstrapPreviousEndpoint)')
    worker = VIDEO.index('self.startWorker(reason: "relay confirmed / \\(reason)", startupBootstrap: true)')
    fetch = VIDEO.index('let snapshots = await self.fetchStartupBootstrapSnapshots(reason: reason)')
    assert current < previous
    assert worker < fetch
    assert 'STARTUP_BOOTSTRAP_LIVE_BRIDGE' in VIDEO
    assert 'bootstrapOverlap(currentSnapshot:' in VIDEO
    assert 'continuous_join=YES' in VIDEO
    assert 'overlap_not_proven' in VIDEO
    assert 'X-U2W-Generation' in VIDEO
    assert 'previousPairIsCoherent' in VIDEO
    assert 'pair=MISMATCH_OR_UNPROVEN' in VIDEO

def test_v838_bootstrap_is_read_only_and_iphone_parsed():
    observer = (V838 / 'u2w_generation_seam_observer.sh').read_text()
    current = (V838 / 'u2wvideo-bootstrap-current.cgi').read_text()
    previous = (V838 / 'u2wvideo-bootstrap-previous.cgi').read_text()
    assert 'cat /proc/$$/fd/9 > "$boot_tmp"' in observer
    assert 'mv "$boot_tmp" "$BOOT_PREV"' in observer
    assert 'cat "$LIVE" > "$TMP"' in current
    assert 'cat "$PREV"' in previous
    assert 'X-U2W-Generation' in current
    assert 'generation-rotated-during-copy' in current
    assert 'X-U2W-Next-Generation' in previous
    assert 'previous-meta-race' in previous
    for text in [observer, current, previous]:
        assert 'AppleCarPlay' not in text or 'never' in text.lower()
    assert 'h264_parse=IPHONE_ONLY' in observer


def test_short_app_switch_uses_bounded_background_task_without_proactive_decoder_reset():
    assert 'beginBackgroundTask(withName: "HUD Map Mode continuity")' in VIDEO
    assert 'background_task_started' in VIDEO
    assert 'background_task_expired' in VIDEO
    assert 'LIFECYCLE PRESERVE' in VIDEO
    assert 'no decoder rebuild, no sanitizer quarantine, no fresh-IDR requirement' in VIDEO


def test_full_canvas_renderer_has_no_legacy_parent_columns():
    assert 'frame(width: 480, height: 240)' in CANVAS
    assert 'HStack(spacing: 0)' not in CANVAS
    for component in ['map', 'speed', 'speedLimit', 'turningStreet', 'maneuver', 'distance', 'lanes', 'eta', 'timeLeft']:
        assert f'.position(canvasPoint(.{component}))' in CANVAS or component == 'eta'
    assert 'designerCanvasPosition(for:' in CANVAS
    assert 'mapFadeHorizontal' in CANVAS and 'mapFadeVertical' in CANVAS


def test_designer_positions_cover_full_480x240_canvas_and_hide_eta_when_shared():
    assert 'min(480, max(0' in SETTINGS
    assert 'min(240, max(0' in SETTINGS
    assert 'Use lane-guidance position for ETA when lanes are unavailable' in UI
    assert '!(state.mapModeSettings.etaUsesLanePositionWhenNoLanes && $0 == .eta)' in UI
    # Legacy group-size control is no longer presented in the active customization stack.
    active = UI.split('private var header: some View', 1)[0]
    assert 'sizeControls' not in active


def test_eta_lane_shared_slot_behavior_and_time_left_independence():
    assert 'if settings.etaUsesLanePositionWhenNoLanes' in CANVAS
    assert 'if !laneGuidanceAvailable' in CANVAS
    assert '.position(canvasPoint(.lanes))' in CANVAS
    assert '.position(canvasPoint(.timeLeft))' in CANVAS
    assert 'etaUsesLanePositionWhenNoLanes = preset.etaUsesLanePositionWhenNoLanes ?? false' in SETTINGS


def test_map_mode_fps_stays_capped_at_15():
    assert 'supportedHUDFrameRates' in SETTINGS
    # The user deliberately chose not to add 20/25 fps.
    line = next(line for line in SETTINGS.splitlines() if 'supportedHUDFrameRates' in line and '[' in line)
    assert '20' not in line and '25' not in line
    assert '15' in line
