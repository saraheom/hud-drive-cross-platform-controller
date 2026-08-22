# v89 iOS 26 Ambient-Light TestFlight Build

This is a temporary build flavor for testing the v89 ambient-light controller
without waiting for the GitHub `xcode-27` preview image to move to the required
Xcode 27 beta.

## What is unchanged

- HUD BLE transport and session rehydration
- Vehicle/OBD controls
- Spotify integration
- Original speed-limit engine
- Existing ELK-BLEDOM presence -> HUD Auto Brightness behavior
- v89 Ambient Lighting discovery, pairing, naming, grouping, Lotus Lantern
  power/RGB/brightness commands, startup fade sequence, reconnect behavior, and
  BLEDIM2 GATT diagnostics

## What is disabled

Only the automatic external-map ScreenCaptureKit/OCR pipeline is removed from
this target.  `Navigation/ExternalNavigationCapture.swift` is not compiled or
linked.  The Navigation tab instead displays an explicit ambient-test banner
and retains only manual navigation packet controls.

The temporary target also omits `screen-capture` from `UIBackgroundModes`.

## GitHub workflow

Run:

`Build and Upload iOS 26 Ambient TestFlight`

from Actions.  The workflow uses `macos-26`, selects Xcode 26.6 when present,
and generates the project from `ios/project-ios26-ambient.yml`.

The existing `Build and Upload iOS TestFlight` workflow is intentionally left
unchanged for the future Xcode 27 build.

## Returning to Xcode 27

No ambient-light code needs to be reimplemented.  Use the normal
`ios/project.yml` and existing Xcode-27 TestFlight workflow again.  The
Xcode-26-only stub files are guarded by `AMBIENT_IOS26_TEST` and therefore do
not declare anything in the normal target.

## v89.1 CI correction

The first v89 push still triggered the legacy `iOS CI` workflow on the
`xcode-27` preview runner. That build exposed one real Swift concurrency error
in the new startup fade helper: the nested async `fade` function lost the
surrounding main-actor isolation and called `sendBrightness` from a nonisolated
context.

v89.1 explicitly marks the helper `@MainActor` and changes the automatic
`iOS CI` workflow to build `project-ios26-ambient.yml` on `macos-26`. The old
Xcode 27 screen-capture CI is preserved as `Future iOS 27 Screen Capture CI
(Manual)` and no longer runs automatically while this temporary branch is in
use.

## v89.2 TestFlight build-number guard

The temporary ambient TestFlight workflow uses `1000 + GITHUB_RUN_NUMBER` as `CFBundleVersion`.
The existing App Store Connect history had already reached build 43 while this newly-created workflow started at run 1, so using the raw workflow run number produced build 1 and App Store Connect rejected it.
The same reserved build-number strategy is now used by the future Xcode 27 TestFlight workflow so returning to the normal capture build does not fall back into the old 1–43 range.
