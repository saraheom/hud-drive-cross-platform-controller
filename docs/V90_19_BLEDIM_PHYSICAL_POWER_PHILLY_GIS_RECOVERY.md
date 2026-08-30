# v90.19 — BLEDIM physical power semantics + Philadelphia GIS provider recovery

## Field evidence

The 2026-08-30 combined-drive log and physical observation established the BLEDIM command-0x80 meaning directly on both BK-BLE controllers:

- App-labelled `Power ON` frame with payload `01` made Door/Dashboard dark.
- App-labelled `Power OFF` frame with payload `00` physically illuminated them.

Therefore the raw protocol recovery was correct but the semantic labels were reversed. v90.19 maps physical ON to `00` and physical OFF to `01`. No other BLEDIM packet grammar or Breath cadence changes.

The successful BLEDIM Breath terminal path remains brightness-only. One-shot recovery may still use the semantic Power ON command when a real failure requires it.

A one-time migration changes the known Door and Dashboard saved `powerOn` values back to `true`, because the v90.18.2 test deliberately stored them as false solely to work around the inverted field mapping.

## Philadelphia GIS

The field log contained 1,894 ArcGIS `Invalid query parameters` errors and no successful City dataset load. The Residential Streets layer does not expose `SpeedLimits_MPH`; v90.18 requested that field from both City layers, so the residential request failed and the combined `async let` result was discarded.

v90.19:

- uses layer-specific `outFields`;
- queries a WGS84 envelope around the GPS point rather than point+distance;
- accepts a valid result from either City layer if the other fails;
- applies a 12-second failure backoff to City GIS and Improved OSM;
- keeps City GIS independent of OSM matching so Philadelphia local-road speed can still resolve during an Overpass outage.

The 4-second stale-sign clearing and warning-threshold safety behavior remain unchanged.
