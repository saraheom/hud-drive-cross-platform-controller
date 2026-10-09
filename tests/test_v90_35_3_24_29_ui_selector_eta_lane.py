from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift").read_text()
CANVAS = (ROOT / "ios/HUDController/MapMode/HudMapModeCanvas.swift").read_text()
FRAME = (ROOT / "ios/HUDController/MapMode/HudMapModeFrameRenderer.swift").read_text()

def test_designer_selector_is_non_scrolling_tap_grid():
    assert "LazyVGrid(" in UI
    assert "GridItem(.adaptive(minimum: 104, maximum: 170)" in UI
    assert "ScrollView(.horizontal, showsIndicators: false)" not in UI
    assert ".contentShape(Rectangle())" in UI

def test_shared_eta_lane_is_mutually_exclusive_in_shared_renderer():
    assert "private var shouldRenderETA: Bool" in CANVAS
    assert "return !laneGuidanceAvailable" in CANVAS
    assert "settings.etaUsesLanePositionWhenNoLanes ? .lanes : .eta" in CANVAS
    assert "if shouldRenderETA" in CANVAS
    assert "phone designer preview and the physical 480x240 JPEG" in CANVAS

def test_eta_is_hidden_from_selector_when_lane_sharing_is_enabled():
    assert "!(state.mapModeSettings.etaUsesLanePositionWhenNoLanes && $0 == .eta)" in UI

def test_preview_and_physical_hud_share_same_canvas_renderer():
    assert UI.count("HudMapModeCanvas(") >= 2
    assert "HudMapModeCanvas(" in FRAME
    assert "settings: settings" in FRAME
