"""Regression: v24.49 music sliders must bind Double settings, not Boolean toggles.

Root cause of GitHub Actions run 111565919019 failure:
NavigationHUDPreviewCard.swift:946 attempted to pass the Bool-only binding(_:) helper
for a musicTitleWidth: Double setting, producing a SwiftUI Binding<Bool> /
Binding<Double> type mismatch.
"""
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / 'ios/HUDController/UI/NavigationHUDPreviewCard.swift'
SETTING_NAMES = (
    'musicTitleWidth', 'musicTitleFontSize', 'musicArtistWidth',
    'musicArtistFontSize', 'musicMarqueeSpeed', 'musicBarHeight',
)


def test_all_numeric_music_sliders_use_explicit_double_binding():
    source = SRC.read_text()
    assert 'private func doubleBinding(_ keyPath: ReferenceWritableKeyPath<HudMapModeSettings, Double>) -> Binding<Double>' in source
    for prop in SETTING_NAMES:
        assert f'doubleBinding(\\.{prop})' in source
        assert f'value: binding(\\.{prop})' not in source
    # Boolean bindings must remain Boolean.
    for prop in ('showMusicOverlay', 'musicTwoLines', 'musicShowProgress'):
        assert f'binding(\\.{prop})' in source


def test_actual_swift_double_keypath_helper_typechecks():
    swiftc = shutil.which('swiftc')
    if swiftc is None:
        import pytest
        pytest.skip('Swift compiler unavailable')
    source = SRC.read_text()
    begin = source.index('    private func doubleBinding(')
    end = source.index('\n    }', begin) + len('\n    }')
    helper = source[begin:end]
    stub = '''
struct Binding<T> {
    let getter: () -> T
    let setter: (T) -> Void
    init(get: @escaping () -> T, set: @escaping (T) -> Void) {
        getter = get
        setter = set
    }
    var wrappedValue: T {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
}
final class HudMapModeSettings {
    var musicTitleWidth = 165.0
    var musicTitleFontSize = 15.0
    var musicArtistWidth = 165.0
    var musicArtistFontSize = 12.0
    var musicMarqueeSpeed = 24.0
    var musicBarHeight = 4.0
}
final class AppState { var mapModeSettings = HudMapModeSettings() }
final class SliderBindingSmoke {
    let state = AppState()
''' + helper + '''
    func typecheckEachSlider() {
''' + ''.join(f'        let _: Binding<Double> = doubleBinding(\\.{n})\n' for n in SETTING_NAMES) + '''
    }
}
'''
    with tempfile.TemporaryDirectory() as directory:
        file = pathlib.Path(directory) / 'SliderBindingSmoke.swift'
        file.write_text(stub)
        subprocess.run([swiftc, '-typecheck', str(file)], check=True, timeout=35)
