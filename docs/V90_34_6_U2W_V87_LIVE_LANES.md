# v90.34.6 — U2W v8.7 live lane guidance

## Data path

`u2wrgd-live.cgi` v8.7 -> optional `laneGuidance` JSON -> maneuver-index cache -> five native HudLauncher lane shapes -> existing Off / Near turn / Persistent coordinator -> `HudLanesManueverCommandPacket (2/113/0)`.

## v8.7 JSON

The client accepts `laneGuidance.sequence`, optional `maneuverIndex`, and ordered lane records containing `index`, `status`, `recommended`, and signed `angles[]`. The object is optional so a v8.6 endpoint still decodes normally.

## Normalization

Angles <= -23 degrees map left, angles >= +23 degrees map right, and the center bucket maps straight. Combined left+straight and straight+right map to the matching stock combination glyphs. The recommendation bit is true when either the exported boolean is true or raw status is 2. An unsupported left+right-only theoretical fork degrades to Straight rather than disturbing navigation.

## Ordering and cache

0x5204 can arrive before the 0x5201 current-maneuver cursor advances. The app caches by lane maneuver index and does not render future lanes. Once the current cursor matches, the cached topology becomes active. A reroute/source change invalidates old cache state.

## Presentation

The v90.34.5 controls are unchanged: Current Street ON/OFF, Lane Guidance Off/Near turn/Persistent, and 0.1-1.0 mi near-turn threshold. Live distance updates only reevaluate when visibility crosses the configured threshold; they do not continuously restart the 1.5-second lane persistence task.

## Diagnostics

First field test should save the HUD app log plus `u2wrgd-status.cgi`, `u2wrgd-live.cgi`, and the v8.7 dump. Relevant app categories are `CARPLAY LANE RX`, `CARPLAY LANE CACHE`, `CARPLAY LANE CURSOR`, `CARPLAY LANE ACTIVATE`, and `HUD LANE POLICY`.

## Safety

Lane decode failures are isolated from normal Route Guidance. The lane parser never owns Navigation ON/OFF and malformed/empty lanes are ignored. No HUD firmware/filesystem writes are introduced.
