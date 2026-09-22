from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ROUTE = (ROOT/'ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift').read_text()
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
AMBIENT = (ROOT/'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
U2W = ROOT/'u2w/v8.15_Reliability'


def test_route_transport_faults_hold_last_valid_navigation():
    assert 'transportFailureHoldoverInterval: TimeInterval = 90.0' in ROUTE
    assert 'malformedResponseHoldoverInterval: TimeInterval = 180.0' in ROUTE
    assert 'CARPLAY RGD HOLD' in ROUTE
    assert 'Route feed interrupted — holding last guidance' in ROUTE
    assert 'inactiveRouteEndConfirmationInterval: TimeInterval = 5.0' in ROUTE
    assert 'Ignoring first inactive sample' in ROUTE


def test_mainvideo_has_freshness_watchdog_and_generation_guard():
    assert 'decoderStaleFrameInterval: TimeInterval = 3.0' in VIDEO
    assert 'sourceStaleInterval: TimeInterval = 15.0' in VIDEO
    assert 'initialIDRWaitDiagnosticInterval: TimeInterval = 20.0' in VIDEO
    assert 'HARD decoder recovery, bounded validated-GOP reseed/fresh-IDR wait' in VIDEO
    assert 'U2W VIDEO WATCH' in VIDEO
    assert 'workerGeneration' in VIDEO
    assert 'self.workerGeneration == generation' in VIDEO


def test_app_consumes_session_scoped_relay_status():
    for token in ['session_id', 'session_discovery_seen', 'session_client_seen', 'session_live_frame_sent']:
        assert token in APP
    assert 'field("hud_mjpeg_established") == "YES"' in APP
    assert 'U2W v8.15' in APP


def test_ambient_preserves_finalized_day_night_and_targets_reconnect_recovery():
    # v90.35.3.24.4 keeps the low-blink reconnect behavior while repairing a
    # stale-Center-identity split-brain: positive Center evidence must reconcile
    # an impossible lightPresent=true / confirmed-DAY state back to NIGHT.
    assert 'if becamePresent || !headlightPowerSessionActive' in AMBIENT
    assert 'positive Center evidence' in AMBIENT
    assert 'paired Center CoreBluetooth didConnect' in AMBIENT

    # Normal physical/headlight reconnects must never arm the blink-prone explicit
    # Power ON preparation. Only a deliberate app-issued manual OFF may do that.
    assert 'bledimExplicitPowerPrimeRequiredIDs' in AMBIENT
    assert 'Manual Power OFF invalidated Already-On Minimal assumption' in AMBIENT
    assert 'bledimExplicitPowerPrimeRequiredIDs.insert(dashboardID)' not in AMBIENT
    assert 'Manual-OFF recovery Power/RGB/brightness prime completed' in AMBIENT

    # Fresh Dashboard reconnects outside a cohort get a quiet boot settle and a
    # brightness-only recovery so an interrupted 0% waveform cannot strand the LEDs.
    assert 'scheduleDashboardReconnectBrightnessRecovery' in AMBIENT
    assert 'Fresh Dashboard reconnect held through boot settle; no Power ON/RGB write' in AMBIENT
    assert 'fresh Dashboard reconnect brightness-only recovery' in AMBIENT
    assert 'Power ON/RGB intentionally omitted' in AMBIENT


def test_bundled_u2w_v815_reliability_payload():
    assert U2W.exists()
    src = U2W/'source'
    streamer = (src/'u2w_mainvideo_streamer.c').read_text()
    route = (src/'u2w_rgd_preload.c').read_text()
    start = (src/'u2whud-start.cgi').read_text()
    stop = (src/'u2whud-stop.cgi').read_text()
    status = (src/'u2whud-status.cgi').read_text()
    assert 'end<pos' in streamer
    assert 'v8.15-rotation-safe' in streamer
    assert 'g_live_json_lock' in route and 'g_media_json_lock' in route
    assert 'session_id' in start
    assert 'Deliberately preserve ingress/discovery/cast daemons' in stop
    for token in ['session_discovery_seen', 'session_client_seen', 'session_live_frame_sent']:
        assert token in status
