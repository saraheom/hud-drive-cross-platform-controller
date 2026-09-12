from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "ios/HUDController/Models/HudMapModeSettings.swift").read_text()
CANVAS = (ROOT / "ios/HUDController/MapMode/HudMapModeCanvas.swift").read_text()
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
THEME = (ROOT / "ios/HUDController/UI/HudTheme.swift").read_text()
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
U2W = ROOT / "u2w/v8.15.1_NoFallbackPrimer"


def test_lane_inactive_gray_is_persisted_and_gray_only():
    assert "laneInactiveGray" in SETTINGS
    assert 'HUD.MapMode.laneInactiveGray' in SETTINGS
    assert 'Color(white: settings.laneInactiveGray)' in CANVAS
    assert "Inactive lane gray" in UI
    assert "0.12...0.80" in UI


def test_map_edge_fade_is_independently_adjustable():
    for token in ["mapFadeHorizontal", "mapFadeVertical"]:
        assert token in SETTINGS
        assert token in CANVAS
    assert "Horizontal fade" in UI
    assert "Vertical fade" in UI
    assert "0.0...0.35" in UI
    assert "edgeFadeMask" in CANVAS


def test_speed_limit_sign_is_number_only_rectangle():
    assert 'Text("SPEED")' not in CANVAS
    assert 'Text("LIMIT")' not in CANVAS
    assert '.frame(width: 42, height: 34)' in CANVAS
    assert 'foregroundStyle(.black)' in CANVAS
    assert '.background(.white)' in CANVAS


def test_map_mode_ui_is_compact_and_legacy_mode5_block_removed():
    assert 'Button("Enable Map Mode")' in UI
    assert 'Button("Disable Map Mode"' in UI
    assert 'CarPlay adapter Wi-Fi name' in UI
    assert 'CarPlay adapter Wi-Fi password' in UI
    assert 'Status & diagnostics' in UI
    assert 'Map Mode image customization' in UI
    assert 'Legacy mode-5 physical HUD test' not in UI
    assert 'Enable Map Mode on HUD' not in UI
    assert '@State private var showRelayDiagnostics = false' in UI
    assert '@State private var showMapCustomization = false' in UI


def test_all_standard_hud_descriptions_default_collapsed():
    assert '@State private var isExpanded = false' in THEME
    assert 'Image(systemName: isExpanded ? "chevron.up" : "chevron.down")' in THEME


def test_app_prewarms_live_frame_before_mode6():
    prewarm = APP.index('Preparing first HUD frame…')
    mode6 = APP.index('IOS_KIVICCAST_STA_MODE(6) [single start]')
    assert prewarm < mode6
    assert 'relay prewarm complete newFrame=' in APP
    assert 'sentFrameCount > prewarmStartCount' in APP


def test_u2w_v8151_uses_live_frame_primer_without_known_fallback():
    assert U2W.exists()
    cast = (U2W / 'source/u2whud_cast_relay.c').read_text()
    assert 'live-primer-frame-sent' in cast
    assert 'waiting-first-live-frame' in cast
    assert 'hold the HUD\'s last frame' in cast
    assert 'fallback-frame-sent' not in cast
    assert 'send_part(c,fallbackbuf' not in cast

