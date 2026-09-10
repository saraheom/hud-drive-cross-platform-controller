# v90.34.17 — Navigation map-video layout preview UI

## Purpose

The CarPlay video work has now produced a decoded MainVideo frame and a usable map crop. Before changing physical-HUD transport/rendering, v90.34.17 adds an in-app layout preview so the proposed composition can be evaluated independently of BLE and firmware behavior.

## Default composition

The preview uses a 2:1 HUD-like canvas:

- **Left:** circular speed presentation plus posted speed-limit sign.
- **Center:** recovered CarPlay map crop, intentionally given the largest share of the canvas.
- **Right:** maneuver icon, distance, upcoming street, compact lane guidance, and ETA.

The center map can use a soft horizontal edge mask so it fades into the black HUD background instead of ending at a hard rectangular boundary.

## Preview controls

The card exposes local-only controls for:

- **Layout:** Left–Center–Right, Map Focus, Minimal.
- **Map Size:** visual scaling of the center crop.
- **Map Crop Position:** horizontal crop offset.
- **Soft Edge Fade:** toggles the map-edge blend.
- **Move Blocks:** nudges the left/right information blocks.

These values intentionally use SwiftUI `@State`; they are not persisted into production HUD settings and do not call AppState HUD senders.

## Live/sample data policy

When live app state is available, the preview reads:

- `OriginalSpeedLimitEngine.currentSpeedMph`
- `OriginalSpeedLimitEngine.currentSpeedLimitMph`
- the current `NavigationInstruction`
- Route Guidance distance and ETA text

While parked with no active route, the preview falls back to sample values so the composition remains visible and tunable.

## Safety / regression boundary

No physical-HUD output path is changed. In particular this build does not modify:

- HUD dashboard/widget packets;
- maneuver or lane packets;
- speed-limit or warning-threshold packets;
- U2W polling or provider selection;
- ambient-light behavior;
- OBD behavior;
- time/weather cold-session synchronization;
- firmware-maintenance behavior.

The next phase can replace the static recovered map crop with a validated live MainVideo frame source once the transport format/rate is finalized.

## Concept references

The two visual concepts used for this build are retained under `docs/concepts/`:

- `HUD_MapVideo_Layout_Concept.png` — proposed physical HUD composition.
- `HUD_Navigation_MapVideo_UI_Concept.png` — proposed Navigation-screen configuration UI.

The runtime preview is implemented natively in SwiftUI rather than displaying the concept screenshot, so later builds can replace the static map crop with live MainVideo without rebuilding the surrounding left/right information blocks.
