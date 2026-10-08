from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
VIDEO = (ROOT / "ios/HUDController/MapMode/U2WMainVideoClient.swift").read_text()
REC = (ROOT / "ios/HUDController/MapMode/LiveMapDiagnosticRecorder.swift").read_text()
ELM = (ROOT / "ios/HUDController/Bluetooth/DirectELM327Manager.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
U2W = ROOT / "u2w/v8.37_ForensicSeamCapture_v835Keyframe_v834Mirror"
OBS = (U2W / "source/u2w_generation_seam_observer.sh").read_text()
INSTALL = (U2W / "source/install_once.sh").read_text()
STATUS = (U2W / "source/u2wvideo-relay-status.cgi").read_text()
BUNDLE = (U2W / "source/u2wvideo-forensic-bundle.cgi").read_text()


def test_release_pair_and_navigation_safety_boundary():
    assert "appVersion=v90.35.3.24.28" in APP
    assert "v90.35.3.24.28 MainVideo client for U2W v8.37 forensic seam capture" in VIDEO
    assert "exact v8.31 raw relay" in VIDEO
    assert "unchanged v8.34 Hard-Bounded Mirror" in VIDEO
    assert "u2wvideo-forensic-status.cgi" in APP
    assert "u2wvideo-forensic-bundle.cgi" in APP
    assert 'evidence.append(("U2W_v8.37_ForensicSeams.tar.gz", forensic))' in APP


def test_first_failure_is_reserved_and_raw_evidence_is_rolling_bounded():
    assert "firstFailurePrebufferLimit = 8 * 1024 * 1024" in REC
    assert "firstFailurePostbufferLimit = 8 * 1024 * 1024" in REC
    assert "FIRST_FAILURE_" in REC
    assert "firstFailureTriggered" in REC
    assert "maximumRollingSegments = 4" in REC
    assert "rollingSegmentLimit = 4 * 1024 * 1024" in REC
    assert "COMPLETENESS_REPORT.txt" in REC
    assert "chunk_fnv1a64" in REC
    assert "chunk_head64" in REC
    assert "chunk_tail64" in REC
    assert 'triggerFirstFailureEvidence("mainvideo_first_failure"' in VIDEO
    assert 'record("parser_decoder_fingerprint", "failure_signal"' in VIDEO


def test_direct_elm_release_waits_for_cancel_ack_and_rejects_late_connects():
    assert "ownershipGeneration" in ELM
    assert "productionConnectGeneration" in ELM
    assert "releaseCancellationPendingIDs" in ELM
    assert "map_obd_late_connect_rejected" in ELM
    assert "LATE CONNECT REJECTED" in ELM
    assert "productionGeneration != self.ownershipGeneration" in ELM
    assert "releaseMapModeOwnershipAndWait(timeout: TimeInterval = 2.5)" in ELM
    assert "releaseCancellationPendingIDs.isEmpty" in ELM
    assert "map_obd_release_confirmed" in ELM
    assert "map_obd_release_timeout" in ELM
    assert "releaseMapModeOwnershipAndWait(timeout: 2.5)" in APP
    assert "resuming HUD ownership" in APP


def test_v837_sidecar_only_captures_binary_seam_evidence():
    assert "passive forensic seam collector" in OBS
    assert 'SAMPLE_BYTES=4096' in OBS
    assert 'tail -c "$SAMPLE_BYTES" /proc/$$/fd/9 > "$old_sample"' in OBS
    assert 'head -c "$SAMPLE_BYTES" "$LIVE" > "$new_sample"' in OBS
    assert "capture_complete=" in OBS
    assert "MAX_EVENTS=128" in OBS
    assert "snapshot_relay_fds" in OBS
    assert "PASSIVE_PROC_SNAPSHOT_ONLY" in INSTALL
    assert "observer_h264_write=NEVER" in INSTALL
    assert "observer_tcp15332_open=NEVER" in INSTALL
    assert "observer_applecarplay_process_control=NEVER" in INSTALL
    assert "mirror_payload_changed_v837=NO" in STATUS
    assert "raw_relay_payload_changed_v837=NO" in STATUS
    assert "keyframe_helper_changed_v837=NO" in STATUS
    assert "forensic bundle creation failed" in BUNDLE


def test_v837_install_refuses_to_modify_nonexact_transport_payloads():
    assert "V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b" in INSTALL
    assert "V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6" in INSTALL
    assert "ABORT v8.34 mirror bytes not exact" in INSTALL
    assert "ABORT v8.31 relay bytes not exact" in INSTALL
    assert "Diagnostics only. Never replace MIRROR/RELAY/helper" in INSTALL
    assert "kill \"$rp\"" not in INSTALL
