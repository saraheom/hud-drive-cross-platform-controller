from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAN = (ROOT / 'ios/HUDController/MapMode/H264MainVideoSanitizer.swift').read_text()
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
VEHICLE = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()
SETTINGS = (ROOT / 'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
ELM = (ROOT / 'ios/HUDController/Bluetooth/DirectELM327Manager.swift').read_text()


def test_v2426_release_keeps_v837_transport_pairing():
    assert 'appVersion=v90.35.3.24.27' in APP
    assert 'v90.35.3.24.27 MainVideo client for U2W v8.37 forensic seam capture' in VIDEO
    assert 'unchanged v8.34 Hard-Bounded Mirror + exact v8.31 raw relay' in VIDEO


def test_foreign_reference_priority_discontinuity_is_rejected_before_videotoolbox():
    assert 'expectedReferenceNALRefIDC' in SAN
    assert 'foreignReferenceRejects' in SAN
    assert 'nalRefIDC != learnedRefIDC' in SAN
    assert 'info.frameNum != expectedFrame' in SAN
    assert 'candidate dropped before VideoToolbox; reference continuity preserved' in VIDEO
    assert 'FOREIGN_REF_IDC_REJECT generation=' in VIDEO
    # Same-priority frame gaps remain telemetry rather than becoming hard drops.
    assert 'treat a single frame_num jump as telemetry' in SAN
    assert 'reference frame_num discontinuity previous=' in SAN


def test_map_mode_ui_is_production_compact_but_diagnostics_remain_collectable():
    assert 'Status & diagnostics' not in UI
    assert 'Parked MainVideo preflight' not in UI
    assert 'Optional MainVideo diagnostics' not in UI
    assert 'Run 90 s OBD deep probe v3' not in UI
    assert 'Collect OBD Drive Diagnostic ZIP (parked)' not in UI
    assert 'Collect Live Map Diagnostic ZIP (parked)' in UI
    assert 'Map Mode FPS' in UI
    assert 'state.mainVideo.transportPhase' in UI


def test_map_mode_fps_remains_capped_at_15():
    assert 'static let supportedHUDFrameRates = [5, 8, 10, 12, 15]' in SETTINGS
    assert '20' not in SETTINGS.split('static let supportedHUDFrameRates =', 1)[1].split('\n', 1)[0]
    assert '25' not in SETTINGS.split('static let supportedHUDFrameRates =', 1)[1].split('\n', 1)[0]


def test_vehicle_direct_elm_surface_is_status_only_and_ownership_logic_is_preserved():
    assert 'section("MAP MODE OBD")' in VEHICLE
    assert 'LabeledContent("Connection", value: state.directELM.ownershipStatus)' in VEHICLE
    assert 'DIRECT ELM327 FEASIBILITY' not in VEHICLE
    assert 'Send one 01 0D speed probe' not in VEHICLE
    assert 'ownershipGeneration' in ELM
    assert 'releaseCancellationPendingIDs' in ELM
    assert 'fullyReleasedForHUD' in ELM
