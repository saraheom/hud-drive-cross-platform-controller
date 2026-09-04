# v90.32.1 — CI XCTest alignment

## Failure observed

The iOS 26 simulator application target compiled successfully. The workflow then failed in the unit-test step with three assertion failures, all from one legacy test:

`V77DistanceAndSpeedWarningTests.testHudManeuverTextCarriesExactSourceDistance()`

That test was written for the v77 OCR workaround, where exact source distance text was deliberately appended to the first maneuver line (for example `Turn right • 0.2 mi`). v90.32 intentionally removed that duplicate text and restored the original HUDWAY presentation, so the old assertions contradicted the new requirement.

## Correction

The legacy source-string test was replaced by a packet-level XCTest that:

1. builds a maneuver containing `displayDistanceText = "0.2 mi"` and `distanceMeters = 321`;
2. unescapes the generated HUD packet;
3. verifies the text payload is exactly the maneuver/street/current-road text and contains neither `0.2 mi` nor `•`;
4. verifies the native Int32 distance field remains exactly `321` meters.

No v90.32 runtime behavior changed.
