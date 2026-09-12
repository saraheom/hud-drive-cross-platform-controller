from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def test_rehydration_is_suppressed_during_live_relay():
    app = (ROOT/'ios/HUDController/App/AppState.swift').read_text()
    assert 'Suppressed during live U2W relay' in app
    assert 'hudRehydrateTask?.cancel()' in app
    assert 'guard !hudU2WLiveRelayActive else' in app

def test_legacy_mode5_ui_is_removed_from_normal_map_mode_surface():
    ui = (ROOT/'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
    assert 'Legacy mode-5 physical HUD test' not in ui
    assert 'Enable Map Mode on HUD' not in ui
    assert 'Button("Enable Map Mode")' in ui

def test_bundled_u2w_v8141_has_persistent_discovery():
    bundled = ROOT/'u2w/v8.14.1_HUD_LiveFrameRelay_Stability'
    assert (bundled/'U2W_Update_v8.14.1_HUD_LiveFrameRelay_Stability.img').exists()
    assert 'persistent' in (bundled/'README.md').read_text().lower()
