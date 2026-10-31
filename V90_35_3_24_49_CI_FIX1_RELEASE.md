# HUD Controller v90.35.3.24.49 — iOS CI FIX1

Based on v24.49 Music Overlay full GitHub ZIP. The Oct. 31 GitHub Actions iOS CI run `111565919019` failed at the iOS Simulator Swift compile step.

## Verified root cause
- File: `ios/HUDController/UI/NavigationHUDPreviewCard.swift`, original line 946.
- Error: `cannot convert value of type 'Binding<Bool>' to expected argument type 'Binding<Double>'` and a `ReferenceWritableKeyPath<..., Double>` to the existing Boolean-only binding helper.
- The new music sliders `musicTitleWidth`, `musicTitleFontSize`, `musicArtistWidth`, `musicArtistFontSize`, `musicMarqueeSpeed`, and `musicBarHeight` were mistakenly passed to `binding(_:)`, which accepts Boolean settings only.

## Fix
- Add `doubleBinding(_ keyPath: ReferenceWritableKeyPath<HudMapModeSettings, Double>) -> Binding<Double>` using the same settings persistence/state as the Boolean binding helper.
- Wire all **six** Music Overlay sliders to `doubleBinding(\.property)`.
- Preserve the three music Boolean controls (`showMusicOverlay`, `musicTwoLines`, `musicShowProgress`) on `binding(_:)`.
- Add regression test `tests/test_v90_35_3_24_49_ci_fix1.py`, including native Swift `-typecheck` of the extracted `doubleBinding` implementation using six `Double` key paths. This prevents a repeat of the same type mismatch even in a non-Apple build environment.

## Scope
Only one original source file changed. The music playback behavior, v24.48 speed-limit continuity, CarPlay/HUD video, U2W adapter firmware, OBD, ambient lighting, maneuvers, CI workflows and all other previous files are byte-for-byte unchanged. No v24.50 features added. Existing presets and their persisted values are preserved.

## Verification
- Python: 645 tests passed, 1 skipped.
- 235 Swift files passed syntax parse.
- Native Swift slider helper `-typecheck`: passed, all 6 numeric keys.
- 8 GitHub Actions YAML files parsed.
- Zip integrity: passed.
- **iOS SDK compilation cannot run on this Linux environment**. Rerun GitHub `iOS CI` to confirm Xcode compilation, followed by `iOS 26 Ambient TestFlight` only if CI is green.
