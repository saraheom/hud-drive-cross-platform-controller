# v90.34.4 — Recorded CarPlay lane replay

This is a zero-firmware-write diagnostic release on top of v90.34.3.

## Goal

Exercise the physical HUD's stock lane renderer at home, without driving and without requiring the CarPlay adapter to be present.

## Source data

The replay fixtures were reconstructed from the user's earlier physical U2W Route Guidance captures:

- Apple Maps: `U2W_RGD_V85_DUMP`, including `0x5204` records 170–175 and 278.
- Google Maps: `U2W_DATA_V86_DUMP`, including `0x5204` records 115–118 and 132–134.

The nested `0x5204 LaneGuidanceInformation` structure contains an ordered lane index, recommendation/status state, and signed direction angles. Angles observed in the physical captures were `-90`, `-45`, `0`, `+45`, and `+90` degrees.

For the stock HUD renderer these are normalized into the five shapes recovered from HudLauncher:

- left
- straight + left
- straight
- straight + right
- right

Recommendation state becomes the existing positive/negative `HudLanesManueverCommandPacket` wire sign.

## UI

Navigation -> Recorded CarPlay lane replay now provides:

- Apple Maps / Google Maps capture selection;
- raw CarPlay lane-angle display;
- resulting native HUD signed values;
- Send This Recorded Step;
- Previous / Next step-and-send controls;
- Auto Replay at four seconds per captured lane event;
- Clear Replayed Lanes.

Each replay step sends the normal native maneuver first and the native lane packet second.

## Safety boundary

The replay does not use ADB, does not contact the HUD filesystem, does not invoke the software updater, and does not modify the live CarPlay adapter parser. It is BLE-only and manually initiated.

Live `0x5204` -> HUD lane integration remains deliberately disabled until the physical renderer behavior is validated with this parked replay.
