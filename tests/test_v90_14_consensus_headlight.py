from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MONITOR = (ROOT / 'ios/HUDController/Vehicle/AmbientLightMonitor.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
SPOTIFY = (ROOT / 'ios/HUDController/Media/SpotifyMediaController.swift').read_text()
SPEED = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
VIEW = (ROOT / 'ios/HUDController/UI/VehicleView.swift').read_text()


def test_headlight_requires_stable_two_controller_consensus():
    assert 'private enum HeadlightConsensusObservation' in MONITOR
    assert 'case bothOn' in MONITOR and 'case bothOff' in MONITOR and 'case mixed' in MONITOR
    assert 'headlightConsensusStabilitySeconds: TimeInterval = 0.75' in MONITOR
    assert 'both Center + Dashboard stable ON' in MONITOR
    assert 'both Center + Dashboard stable OFF' in MONITOR
    assert 'preserving confirmed' in MONITOR
    assert 'setAuthoritativeHeadlightPower' not in MONITOR


def test_headlight_animation_waits_for_both_gatt_controllers():
    assert 'private func tryStartConfirmedHeadlightBreath' in MONITOR
    assert 'isControllable(dashboardID)' in MONITOR
    assert 'isControllable(centerID)' in MONITOR
    assert 'Consensus headlight animation admitted' in MONITOR
    assert 'queuePowerUpBreath(id)' in MONITOR
    assert 'Same-epoch headlight reconnect → steady restore' in MONITOR
    assert 'restoreDeviceState(id)' in MONITOR


def test_v9010_transport_baseline_is_retained():
    assert 'private var bledimSequenceByID: [UUID: UInt8]' in MONITOR
    assert 'protocolPacing=20Hz/rawBLEDIM' in MONITOR
    assert 'private func sendPowerWhenReady' in MONITOR
    assert 'private func sendColorWhenReady' in MONITOR
    assert 'private func applyRuntimeBrightnessWhenReady' in MONITOR
    assert 'Steady-state recovery begin' not in MONITOR
    assert 'BLEDIM10Hz' not in MONITOR


def test_hud_auto_brightness_uses_consensus_not_center_alone():
    assert 'Headlight consensus → Auto brightness ON' in MONITOR
    assert 'Headlight consensus → Auto brightness OFF' in MONITOR
    assert 'HUD rehydrate → consensus auto brightness' in MONITOR
    assert 'tracked Center presence remains useful for UI/status' in MONITOR


def test_newer_independent_features_are_kept():
    assert 'updateOverspeedWarning' in APP
    assert 'setAutomaticVehicleWakeAllowed' in SPOTIFY
    assert 'case enhancedOSM = "Enhanced OSM"' in SPEED
    assert 'case traceOSM = "OSM Trace"' in SPEED
    assert 'AMBIENT OVERSPEED WARNING' in VIEW
    assert 'overspeedWarningColor' in MONITOR
    assert 'overspeedWarningCooldownSeconds: TimeInterval = 60.0' in MONITOR
    assert 'max(0.0, min(5.0, overspeedWarningPulseDurationSeconds))' in MONITOR


def test_legacy_v9012_xctest_is_overwritten_for_overlay_updates():
    compatibility_test = ROOT / 'ios/HUDControllerTests/V9012AmbientRecoveryOverspeedSpotifyGateTests.swift'
    assert compatibility_test.exists()
    text = compatibility_test.read_text()
    assert 'testHeadlightStateRequiresStableTwoControllerConsensus' in text
    assert 'testSameEpochReconnectUsesSingleSteadyRestoreInsteadOfBreathReplay' in text
    assert 'scheduleRobustSteadyStateRecovery' in text  # asserted absent by XCTest
    assert 'testBLEDIMAnimationRateAndFailSafeRecovery' not in text
    assert 'testRapidHeadlightEdgesInvalidateEntireOldBreathTimeline' not in text
