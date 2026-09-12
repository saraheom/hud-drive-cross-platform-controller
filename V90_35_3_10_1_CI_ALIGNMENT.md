# v90.35.3.10.1 — XCTest CI alignment

The v90.35.3.10 runtime/UI changes compiled successfully in GitHub Actions, but one legacy source-string XCTest still expected the removed heading `Live iPhone → U2W → HUD relay`.

This point release updates only that test to validate the new compact Map Mode controls (`Enable Map Mode`, collapsed `Status & diagnostics`, `Frame ingress`, and `Frames sent`). No production Swift source was changed from v90.35.3.10. U2W v8.15.1 is unchanged.
