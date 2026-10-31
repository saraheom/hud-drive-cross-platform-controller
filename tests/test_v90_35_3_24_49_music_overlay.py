"""v24.49 HUD music customization and runtime wiring regression."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import pytest

ROOT = Path(__file__).resolve().parents[1]
MODELS = (ROOT / 'ios/HUDController/Models/HudMapModeSettings.swift').read_text()
SNAP = (ROOT / 'ios/HUDController/MapMode/HudMapModeSnapshot.swift').read_text()
CANVAS = (ROOT / 'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()
APP = (ROOT / 'ios/HUDController/App/AppState.swift').read_text()
MEDIA = (ROOT / 'ios/HUDController/Media/CarPlayNowPlayingClient.swift').read_text()
UI = (ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift').read_text()
POLICY = ROOT / 'ios/HUDController/MapMode/HudMapMusicBehavior.swift'


def test_music_is_independent_of_navigation_and_renders_on_hud_and_phone():
    assert 'if settings.showMusicOverlay && snapshot.musicPlaying' in CANVAS
    assert '.position(canvasPoint(.music))' in CANVAS
    assert 'musicOverlay\n' in CANVAS
    assert 'HudMapModeFrameRenderer.jpeg' in APP
    assert 'HudMapModeCanvas(' in UI
    # The music block must be outside the hasLiveRoute conditional.
    section = CANVAS.split('private var canonicalCanvas: some View {', 1)[1].split('private func musicMarqueeOffset', 1)[0]
    assert section.rindex('if settings.showMusicOverlay && snapshot.musicPlaying') > section.rindex('if snapshot.hasLiveRoute')
    assert 'sourceMapImage' in CANVAS


def test_two_layouts_symbol_and_line_widths():
    assert 'case music' in MODELS
    assert 'let firstText = settings.musicTwoLines' in CANVAS
    assert 'joined(separator: ", ")' in CANVAS
    assert 'Image(systemName: "music.note")' in CANVAS
    assert 'if settings.musicTwoLines && !snapshot.musicArtist.isEmpty' in CANVAS
    assert 'musicArtistWidth' in MODELS
    assert 'musicTitleWidth' in MODELS
    assert 'musicTitleFontSize' in MODELS
    assert 'musicArtistFontSize' in MODELS


def test_progress_width_tied_to_first_line_and_clamped():
    assert '.frame(width: titleWidth, height: CGFloat(max(2, min(10, settings.musicBarHeight))))' in CANVAS
    assert 'Double(snapshot.musicElapsedMs) / Double(snapshot.musicDurationMs)' in CANVAS
    assert 'if settings.musicShowProgress && snapshot.musicDurationMs > 0' in CANVAS
    assert 'geometry.size.width * progress' in CANVAS
    assert 'HudMapMusicBehavior.interpolatedElapsedMs' in APP


def test_media_fetch_and_auto_hide_not_bound_to_map_route():
    assert 'let mediaVisible = HudMapMusicBehavior.isVisible(' in APP
    assert 'playing: nowPlaying.isPlaying' in APP
    assert 'ageSeconds: mediaAge' in APP
    assert 'musicPlaying: mediaVisible' in APP
    assert 'frozen.musicPlaying = current.musicPlaying' in APP
    assert 'snapshot.playbackStatus != 2' in MEDIA
    assert 'private(set) var lastTrackChangedAt: Date?' in MEDIA
    assert 'musicTrackAgeSeconds: musicAge' in APP


def test_preset_migration_settings_and_designer():
    for name in ('showMusicOverlay', 'musicTwoLines', 'musicShowProgress',
                 'musicTitleWidth', 'musicArtistWidth', 'musicTitleFontSize',
                 'musicArtistFontSize', 'musicBarHeight', 'musicTextRed',
                 'musicBarBlue', 'musicOffsetX', 'musicOffsetY'):
        assert f'var {name}:' in MODELS
        assert f'preset.{name}' in MODELS
        assert f'settings.{name}' in MODELS if name not in ('musicOffsetX', 'musicOffsetY') else True
    assert 'selectedDesignerComponent = .music' in UI
    assert 'musicOverlayControls' in UI
    assert 'supportsOpacity: false' in UI
    assert 'musicMarqueeSpeed' in UI
    assert 'showMusicOverlay = bool("HUD.MapMode.Music.visible", default: true)' in MODELS


def test_existing_performance_and_sources_untouched():
    assert 'let targetFPS = HudMapModeSettings.supportedHUDFrameRates.max() ?? 15' in APP
    assert 'startHUDU2WRelayFrameLoop()' in APP
    assert 'self.mainVideo.start(reason: "physical Map Mode live source (optional)")' in APP
    assert 'nowPlaying.start(reason: "HUD BLE transport ready")' in APP
    assert 'HudMapMusicBehavior.marqueeOffset(' in CANVAS


def test_native_swift_music_policy_replay():
    compiler = shutil.which('swiftc')
    if not compiler:
        pytest.skip('Native Swift compiler unavailable in this environment')
    with tempfile.TemporaryDirectory() as d:
        binary = Path(d) / 'replay'
        subprocess.run([compiler, str(POLICY), str(ROOT / 'tools/replay_music_overlay.swift'), '-o', str(binary)], check=True, timeout=40)
        subprocess.run([str(binary)], check=True, timeout=10)
