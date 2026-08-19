# TestFlight workflow recovery

This repository contains the current v88 application source unchanged.

Only `.github/workflows/ios-testflight.yml` was restored to the exact workflow
from successful v86 commit `a7eb700`.

That successful workflow uses the existing repository secrets:

- IOS_BUNDLE_ID
- APPLE_TEAM_ID
- IOS_DISTRIBUTION_P12_BASE64
- IOS_DISTRIBUTION_P12_PASSWORD
- IOS_APPSTORE_PROFILE_BASE64
- ASC_KEY_ID
- ASC_ISSUER_ID
- ASC_KEY_P8_BASE64
- SPOTIFY_CLIENT_ID

No new secrets are required.

The current application code, including all v87/v88 runtime changes, is
otherwise unchanged.
