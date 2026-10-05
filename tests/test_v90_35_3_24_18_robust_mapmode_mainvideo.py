from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
RELAY = (ROOT / "ios/HUDController/MapMode/U2WHUDFrameRelayClient.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
SAN = (ROOT / "ios/HUDController/MapMode/H264MainVideoSanitizer.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()


def test_physical_map_mode_is_fallback_first_again():
    assert 'physical Map Mode live source (optional)' in APP
    assert 'Preparing first HUD Map Mode frame' in APP
    assert 'guard firstFrameDelivered else' in APP
    assert 'physical Map Mode no longer depends on MainVideo readiness' in APP
    assert 'sourceMapImage: freshLiveMapImage' in APP
    assert 'age < 1.5' in APP


def test_tcp15331_waiting_or_preparing_cannot_stall_forever():
    assert 'case .preparing:' in RELAY
    assert 'case .waiting(let error):' in RELAY
    assert 'armConnectDeadline(for: c, reason: reason)' in RELAY
    assert 'Task.sleep(for: .seconds(2.5))' in RELAY
    assert 'connect deadline expired' in RELAY
    assert 'func ensureConnection(reason: String)' in RELAY
    assert 'HUD STA link-up status=' in APP


def test_mode6_handoff_requires_an_actual_accepted_jpeg_not_mainvideo():
    prewarm = APP.index('Preparing first HUD Map Mode frame')
    sent_guard = APP.index('guard firstFrameDelivered else', prewarm)
    mode6 = APP.index('HudCommands.kivicMode(6)', sent_guard)
    assert prewarm < sent_guard < mode6
    assert 'self.hudU2WFrameRelay.sentFrameCount > prewarmStartCount' in APP


def test_codec_bad_data_recovery_preserves_validated_parameter_sets_and_tcp():
    assert 'decoder.hardRecoverAwaitingFreshCodecEpoch(reason: reason)' in VIDEO
    assert 'sanitizer.reset(clearParameterSets: true)' in VIDEO
    assert "reconnecting TCP ONCE for the adapter's validated current-generation checkpoint" in VIDEO
    assert 'checkpoint already attempted in this recovery episode; no reconnect loop' in VIDEO
    assert 'func quarantineReferenceChainUntilIDR()' in SAN


def test_combined_release_keeps_u2w_v831_unchanged():
    assert 'v90.35.3.24.23 pairs with U2W v8.35 Bounded KeyFrame Request + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 Raw Relay' in UI
    assert 'no adapter H.264 parser/cache, source reacquisition, autostart, AppleCarPlay/ARMiPhoneIAP2 process control' in UI
    assert 'appVersion=v90.35.3.24.23' in APP
