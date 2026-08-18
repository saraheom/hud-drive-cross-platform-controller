# v88 TestFlight — no-new-secrets workflow fix

This version removes the proposed `APPLE_ID` / `FASTLANE_SESSION` requirement.

## What it changes

The existing GitHub `xcode-27` runner is retained.

At the beginning of the job, the workflow:

1. enumerates every `/Applications/Xcode*.app` installed on the runner;
2. reads each Xcode 27 build number;
3. selects the newest one with `xcode-select`;
4. checks that it is newer than the known-rejected Xcode 27 beta 4 build
   (`27A5228h`);
5. continues with the existing signing, archive, IPA export, and TestFlight
   upload steps unchanged.

If GitHub still gives the job only beta 4, the job fails in the first few
seconds instead of spending minutes archiving an IPA that App Store Connect
will reject.

## No setup changes

Do NOT add:

- APPLE_ID
- FASTLANE_SESSION

Do NOT install Fastlane/Ruby on the Windows PC for this fix.

Keep all of the GitHub secrets that were already working before v87.

## Install

Replace:

`.github/workflows/ios-testflight.yml`

with the supplied file, commit, push, and run **iOS TestFlight**.

## Important limitation

This workflow cannot manufacture a newer Xcode toolchain. If GitHub's
`xcode-27` image still contains only beta 4, there is no no-secret,
GitHub-hosted workflow-only way to produce a TestFlight-acceptable iOS 27
binary. The job will say that explicitly and stop early.

As soon as GitHub rolls a newer Xcode 27 into the same runner label, this
workflow automatically selects it and resumes the normal TestFlight pipeline
without another repository change.
