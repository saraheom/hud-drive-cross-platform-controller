# v90.11.1 — No-billing speed-limit source testing

This maintenance release removes HERE completely and keeps the v90.11 ambient/Spotify behavior unchanged.

The Speed + Speed Limit source picker is now:

- Current — original HUDWAY/decompiled OSM matcher, unchanged.
- Enhanced OSM — directional + continuity matcher on OpenStreetMap data.
- OSM Trace — rolling GPS-trace matcher performed locally against OSM road geometry.

No HERE credentials, HERE endpoint, Keychain entry, or commercial map API remain in the application.

OSM Trace keeps up to eight recent moving GPS samples for scoring. It gives greater weight to recent points, compares distance and travel direction against candidate road geometry, resists switching unless the new road has a confidence advantage for repeated samples, and supports conservative time/day conditional speed limits.

The app still obtains nearby road geometry through the same public Overpass endpoint used by the original matcher. Public Overpass service can throttle or be temporarily unavailable, so this is a no-billing test source rather than an SLA-backed service.
