from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIDEO = (ROOT/'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()
SAN = (ROOT/'ios/HUDController/MapMode/H264MainVideoSanitizer.swift').read_text()
APP = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
ROOTVIEW = (ROOT/'ios/HUDController/UI/RootView.swift').read_text()

def test_v2428_generalized_one_picture_quarantine_is_production_path():
    assert 'func processBatch(_ nal: Data) -> [H264SanitizedNAL]' in SAN
    assert 'grossContinuityDistanceThreshold: UInt32 = 8' in SAN
    assert 'old_cadence_resumed' in SAN
    assert 'persistent_shift_next=' in SAN
    assert 'AU_CONTINUITY_QUARANTINE' in VIDEO
    assert 'sanitizer.processBatch(nal)' in VIDEO
    assert '3170->3999->3171' in VIDEO
    assert '2239->1151->2240' in VIDEO

def test_v2428_small_gaps_still_flow_and_staged_recovery_remains():
    assert 'Small gaps (for example 1656 -> 1658) are never held' in SAN
    assert 'CODEC_BAD_DATA_GRACE_ARMED' in VIDEO
    assert 'CODEC_BAD_DATA_GRACE_RECOVERED' in VIDEO
    assert 'CODEC_BAD_DATA_GRACE_EXHAUSTED' in VIDEO

def test_v2428_scene_inactive_does_not_manufacture_idr_dependency():
    assert 'VideoToolbox + reference chain PRESERVED' in VIDEO
    assert 'no decoder rebuild, no sanitizer quarantine, no fresh-IDR requirement' in VIDEO
    assert 'Decoder lifecycle preserve reason=' in VIDEO
    assert 'VTDecompressionSessionInvalidate(decompressionSession)' in VIDEO  # still exists for real hard reset paths
    lifecycle = VIDEO[VIDEO.index('func suspendDecoderForLifecycle'):VIDEO.index('func reconnectAtLiveEdge')]
    assert 'hardRecoverAwaitingIDR' not in lifecycle
    assert 'quarantineReferenceChainUntilIDR' not in lifecycle
    assert 'waitingForFreshLiveIDRAfterRejectedAnchor = true' not in lifecycle
    assert 'preserving TCP/HUD cast source and existing VideoToolbox/reference chain' in ROOTVIEW

def test_v2428_reserved_corruption_window_not_taken_by_generic_recovery_callback():
    callback = VIDEO[VIDEO.index('worker.onDecoderRecovery'):VIDEO.index('worker.onKeyframeRequestNeeded')]
    assert 'triggerFirstFailureEvidence' not in callback
    diagnostic = VIDEO[VIDEO.index('worker.onDiagnostic'):VIDEO.index('self.worker = worker')]
    assert 'let isFirstFailureSignal =' in diagnostic
    assert 'codecBadDataErr' in diagnostic
    assert '-8969' in diagnostic

def test_v2428_version_and_u2w_pairing():
    assert 'appVersion=v90.35.3.24.29' in APP
    assert 'v90.35.3.24.29 MainVideo client for U2W v8.38' in VIDEO
