from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
SETTINGS = (ROOT / 'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
CANVAS = (ROOT / 'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
VEHICLE = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()
OBD = (ROOT / 'ios/HUDController/Vehicle/HudOBDController.swift').read_text()


def test_v2423_accepts_actual_v835_status_markers_before_tcp_open():
    assert 'let v835Marker = fields["v835_marker"] ?? "?"' in VIDEO
    assert 'let v834MirrorMarker = fields["v834_mirror_marker"] ?? "?"' in VIDEO
    assert 'legacyMarker == "YES" || v835Marker == "YES" || v834MirrorMarker == "YES"' in VIDEO
    assert 'process == "RUNNING" && compatibleMarker && supportedRelay' in VIDEO
    assert 'markers={legacy=' in VIDEO
    assert 'startWorker(reason: "relay confirmed / \\(reason)", startupBootstrap: true)' in VIDEO


def test_v2423_keeps_v835_keyframe_and_v834_raw_transport_contract():
    assert 'v8.35-bounded-keyframe-v834-hardmirror-v831-raw-tcp-15332' in VIDEO
    assert 'u2wvideo-request-keyframe.cgi' in VIDEO
    assert 'keyframeRequestCooldown: TimeInterval = 10.0' in VIDEO
    assert 'reconnectAtLiveEdge(reason: "lifecycle' not in VIDEO


def test_v2423_winding_wy_lane_clear_has_guarded_delayed_clear():
    assert 'Winding Wy field case' in APP
    assert 'Lane renderer reset → guarded settle clear' in APP
    assert 'guarded settle clear after renderer recreation' in APP
    assert 'self.lanePresentationGeneration == generation' in APP
    assert 'self.activeLaneGuidance.isEmpty' in APP
    assert 'milliseconds(450)' in APP


def test_v2423_eta_ampm_toggle_is_global_and_defaults_on():
    assert 'var showETAAMPM: Bool' in SETTINGS
    assert 'HUD.MapMode.showETAAMPM' in SETTINGS
    assert 'showETAAMPM = bool("HUD.MapMode.showETAAMPM", default: true)' in SETTINGS
    assert 'Toggle("Show AM/PM in ETA"' in UI
    assert 'etaDisplayText(snapshot.etaText)' in CANVAS
    assert 'suffix == "AM" || suffix == "PM"' in CANVAS


def test_v2423_obd_manual_ownership_controls_are_explicit_and_logged():
    assert 'Connect via HUD' in VEHICLE
    assert 'section("MAP MODE OBD")' in VEHICLE
    assert 'state.directELM.ownershipStatus' in VEHICLE
    assert 'Map Mode now owns OBD from the iPhone automatically' in VEHICLE
    assert 'OBD OWNERSHIP' in OBD
    assert 'HUD auto-connect=' in OBD
    assert 'manual HUD connect request' in OBD
    assert 'manual HUD disconnect request' in OBD


def test_v2423_current_release_strings_are_aligned():
    assert 'appVersion=v90.35.3.24.29' in APP
    assert 'v90.35.3.24.29 MainVideo client for U2W v8.38 read-only startup bootstrap + v8.37 forensic seam capture + unchanged v8.35 helper + unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay' in VIDEO
