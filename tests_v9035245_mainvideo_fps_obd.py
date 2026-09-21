from pathlib import Path
ROOT = Path(__file__).resolve().parent
mv = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
relay = (ROOT/'ios/HUDController/MapMode/U2WHUDFrameRelayClient.swift').read_text()
app = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
settings = (ROOT/'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
ui = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
obd = (ROOT/'ios/HUDController/Vehicle/HudOBDController.swift').read_text()
bt = (ROOT/'ios/HUDController/Bluetooth/HudBluetoothManager.swift').read_text()

def test_mainvideo_one_reseed_then_preserve_tcp():
    assert 'recentAnchorRecoveryUsed' in mv
    assert 'waitingForFreshLiveIDRAfterRejectedAnchor' in mv
    assert 'TCP PRESERVED, quarantining replay and waiting for next live IDR' in mv
    assert 'delay: 0.35' in mv
    assert 'WAITING_FRESH_IDR' in mv

def test_fps_probe_discrete_and_measured():
    assert 'supportedHUDFrameRates = [5, 8, 10, 12, 15]' in settings
    assert 'HUD.MapMode.hudFrameRate' in settings
    assert 'recentKilobytesPerSecond' in relay
    assert 'actualFPS' in relay
    assert '1000.0 / Double(targetFPS)' in app
    assert 'HUD map FPS probe' in ui

def test_obd_probe_v2_non_disruptive():
    assert 'vehicleSpeedPIDSupported' in obd
    assert 'PID 0x0D advertised: YES' in obd
    assert '45 s hidden item-10 trace — GPS display unchanged' in app
    assert 'fullscreen=unchanged' in app
    assert 'OBD PROBE SUMMARY' in bt
    assert '45 s OBD speed probe v2' in ui

def test_no_new_u2w_requirement_in_release_notes():
    notes = (ROOT/'V90_35_3_24_5_RELEASE.md').read_text()
    assert 'U2W v8.24 is unchanged and does not need to be reflashed' in notes
