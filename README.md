# v88 — restore v86 TestFlight build path

This patch changes only `.github/workflows/ios-testflight.yml`.

It does NOT revert any v88 app code.

The workflow now behaves like the successful v86 TestFlight run:

- uses `runs-on: xcode-27`;
- uses the Xcode selected by that runner;
- prints the Xcode version/build for diagnostics;
- validates the iPhoneOS SDK;
- generates the project;
- installs the same signing certificate/profile;
- archives the current repository source;
- exports the App Store IPA;
- uploads it with the existing App Store Connect API-key / Fastlane flow.

Removed:
- the early rejection of Xcode 27 beta 4 / build `27A5228h`;
- the extra Xcode-selection guard;
- any requirement for APPLE_ID or FASTLANE_SESSION.

This means v88 source is built exactly through the same pipeline style that
successfully uploaded v86 earlier on 2026-08-18.

Install:
1. Replace `.github/workflows/ios-testflight.yml` with the supplied file.
2. Commit and push.
3. Run `iOS TestFlight`.
