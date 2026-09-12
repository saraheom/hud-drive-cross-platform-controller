from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "ios/HUDController/UI/NavigationHUDPreviewCard.swift"
NAV = ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift"
ASSET = ROOT / "ios/HUDController/Assets.xcassets/CarPlayMapPreview.imageset/CarPlayMapPreview.png"
README = ROOT / "README.md"

def test_navigation_map_mode_ui_remains_integrated():
    assert PREVIEW.exists()
    source = PREVIEW.read_text()
    nav = NAV.read_text()
    assert 'Text("Custom Map Mode")' in source
    assert 'HudMapModeCanvas(' in source
    assert 'NavigationHUDPreviewCard(state: state)' in nav
    assert ASSET.exists() and ASSET.stat().st_size > 10_000

def test_evolved_preview_exposes_independent_size_crop_and_component_controls():
    source = PREVIEW.read_text()
    for token in [
        'Text("Independent widget size")',
        'title: "Left widget"',
        'title: "Center map"',
        'title: "Right widget"',
        'Text("Live map crop")',
        'title: "Map zoom"',
        'title: "Crop X"',
        'title: "Crop Y"',
        'Text("Visible components")',
    ]:
        assert token in source

def test_map_mode_ui_reads_centralized_snapshot_and_live_mainvideo_source():
    source = PREVIEW.read_text()
    assert 'state.mapModePreviewSnapshot' in source
    assert 'state.mapModePreviewSourceImage' in source
    assert 'state.mainVideo.status' in source
    assert 'state.mainVideo.frameCount' in source

def test_release_notes_preserve_v903417_history():
    readme = README.read_text()
    assert '# v90.34.17 — Navigation map-video layout preview UI' in readme
    assert 'v90.34.17 builds directly on v90.34.16.1' in readme
    assert 'does **not** change HUD BLE packets' in readme
