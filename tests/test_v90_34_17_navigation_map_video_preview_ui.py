from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift"
NAV = ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift"
ASSET = ROOT / "ios/HUDController/Assets.xcassets/CarPlayMapPreview.imageset/CarPlayMapPreview.png"
README = ROOT / "README.md"


def test_navigation_map_video_preview_is_integrated():
    assert PREVIEW.exists()
    source = PREVIEW.read_text()
    nav = NAV.read_text()
    assert 'Text("Map Video Display (Preview)")' in source
    assert 'Image("CarPlayMapPreview")' in source
    assert 'NavigationHUDPreviewCard(state: state)' in nav
    assert ASSET.exists() and ASSET.stat().st_size > 10_000


def test_preview_exposes_requested_layout_controls():
    source = PREVIEW.read_text()
    for token in [
        'Text("Layout")',
        'title: "Map Size"',
        'title: "Map Crop Position"',
        'Label("Soft Edge Fade"',
        'Label("Move Blocks"',
        'case leftCenterRight',
        'case mapFocus',
        'case minimal',
    ]:
        assert token in source


def test_preview_uses_existing_live_state_without_owning_hud_transport():
    source = PREVIEW.read_text()
    assert 'state.speedEngine.currentSpeedMph' in source
    assert 'state.speedEngine.currentSpeedLimitMph' in source
    assert 'state.navigation.current.maneuver' in source
    assert 'state.routeGuidance.etaText' in source
    assert 'state.routeGuidance.distanceToManeuverText' in source

    # Preview is intentionally non-invasive in v90.34.17.
    for forbidden in [
        'bluetooth.enqueue',
        'HudCommands.',
        'navigation.navigationOn()',
        'navigation.navigationOff()',
        'routeGuidance.start(',
        'routeGuidance.stop(',
    ]:
        assert forbidden not in source


def test_release_notes_preserve_v9034161_as_base():
    readme = README.read_text()
    assert readme.startswith('# v90.34.17 — Navigation map-video layout preview UI')
    assert 'builds directly on v90.34.16.1' in readme
    assert 'does **not** change HUD BLE packets' in readme
