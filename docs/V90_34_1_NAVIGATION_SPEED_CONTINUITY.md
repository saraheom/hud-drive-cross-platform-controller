# v90.34.1 — Route Guidance cursor compatibility + persistent road speed continuity

## Field failures addressed

The September 5 field capture showed two independent regressions in the v90.34 + U2W v8.6 pair:

1. Google Maps Route Guidance was visible in the iPhone app but never activated the physical HUD. Apple Maps could activate the HUD but then remain stuck on an old maneuver for minutes.
2. Roosevelt Expressway repeatedly displayed a valid 50 mph limit and then blanked the sign while traversing untagged OSM pieces before later finding another explicit limit.

## Route Guidance: U2W v8.6 single-index compatibility

CarPlay `0x5201` field `0x000D` is a list of currently relevant maneuver indexes. The first valid element is the primary/current maneuver. U2W v8.6 accidentally exports a one-element list as `nextManeuverIndex` while leaving `currentManeuverIndex` null. That one-element form dominated both Google Maps and Apple Maps normal updates in the field dump.

v90.34.1 resolves the primary index in this order:

1. first valid element of optional future `currentManeuverIndices[]`;
2. valid legacy `currentManeuverIndex`;
3. **only when the legacy current field is absent**, a valid `nextManeuverIndex` that exists in the maneuver table (v8.6 single-index compatibility).

When both legacy fields are present, the second field is never promoted. This preserves the v90.32 fix for Apple Maps frames where the second list member is simultaneously relevant/following rather than the current HUD instruction. `0xFFFF` remains invalid and there is still no `maneuvers.first` fallback.

Transport liveness is unchanged from v90.34: a successful `u2wrgd-live.cgi` response keeps an active route alive even if its sequence is unchanged at a stoplight.

## Speed limits: road-episode continuity across untagged OSM bridges

OSM may switch semantic identity inside one physical corridor because `normalizedRoadIdentity` intentionally prefers a road name over a route ref. The field example was effectively:

`Roosevelt Expressway / US 1 / motorway / 50 mph`
→ `unnamed / US 1 / motorway_link / no maxspeed`
→ `Roosevelt Expressway / US 1 / motorway / 40 mph`

The old hard-road takeover treated `name:roosevelt expressway` → `ref:us 1` as a different road and disarmed the display cache, allowing the sign to clear after four seconds.

v90.34.1 recognizes an **untagged corridor bridge** only when:

- a confirmed speed is already displayed;
- the newly selected OSM segment has no explicit speed;
- previous and new OSM segments share the same normalized road name or route ref;
- their highway classes belong to the same mainline/link family (e.g. `motorway` and `motorway_link`);
- the existing matcher has already accepted the new segment using its strict live geometry gates.

The displayed number is then transferred to the new road/ref identity and can remain visible for as long as live same-corridor geometry continues. This inherited value is **display-only** and does not refresh overspeed-warning trust. A newly encountered explicit conflicting limit is not bridged and therefore takes over through the existing two-sample source confirmation.

## Warning-threshold stability

A strong local explicit source that is merely reconfirming the same displayed mph no longer forces the native warning threshold through `mph → 0 → mph` during the one-sample confirmation handoff. Inferred/display-only sources still disable warning trust immediately.

## Unchanged

- CarPlay Now Playing and artwork from U2W v8.6.
- Google Maps > Apple Maps > Waze source priority.
- reroute stabilization and native ETA.
- no OCR fallback.
- ambient-light behavior.
- legal speed values still come only from OSM / Philadelphia GIS; CarPlay supplies road context, never a speed value.
