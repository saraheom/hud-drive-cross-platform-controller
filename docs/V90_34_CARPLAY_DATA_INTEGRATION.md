# v90.34 — CarPlay data integration

v90.34 is paired with U2W CarPlay Data Exporter v8.6. It combines the September 4 navigation/speed-limit field findings with the already-proven CarPlay Now Playing traffic from the physical adapter.

## Navigation liveness: endpoint reachability, not sequence movement

Apple Maps can leave a valid active `0x5201` state unchanged for tens of seconds while stopped at a traffic light. Route Guidance `sequence` is therefore a data-change counter, not a transport heartbeat.

v90.34 refreshes the selected-source lease on every successful HTTP response from `u2wrgd-live.cgi`, even when the sequence is unchanged. The HUD stays in Navigation while the endpoint remains reachable and the snapshot remains active. A real `routeState=0` / `active=false` still exits Navigation immediately except for the existing observed reroute grace. If the endpoint cannot be successfully refreshed for 4.5 seconds, the cached lease expires and the HUD returns to Freeride.

The existing Google Maps > Apple Maps > Waze priority and reroute stabilization remain in place.

## Route Guidance connected-corridor speed consensus

The afternoon MLK field drive showed that Route Guidance identified `Martin Luther King Dr` immediately after the Sweetbriar turn, but the nearby OSM ways were untagged for `maxspeed`. Explicit 25 mph OSM ways existed farther down the same connected MLK corridor.

When Improved + Philly mode has all of the following:

- a confirmed nearby OSM road with no explicit speed;
- compatible current GPS geometry;
- fresh CarPlay `currentRoad` matching that OSM road;
- a non-transition Route Guidance state;

v90.34 schedules a bounded one-time Overpass lookup for the exact OSM road name. The radius is `next maneuver distance + 600 m`, clamped to 1.5–3.0 km. Returned same-road ways are reduced to the graph-connected component containing the current way (or nearest returned seed). A speed is inferred only when at least two connected ways have explicit speeds and **all explicit speeds agree**.

The inferred value is displayed as `OSM Route Guidance corridor consensus` and is intentionally **not warning-eligible**. Overspeed warning continues to require a stronger local/explicit speed source. Conflicting corridor speeds cause the inference to be withheld.

CarPlay still never supplies the posted speed itself.

## CarPlay Now Playing replaces Spotify runtime integration

The U2W v8.6 endpoint is polled at:

`http://192.168.50.2/cgi-bin/u2wmedia-live.cgi`

Artwork is fetched from:

`http://192.168.50.2/cgi-bin/u2wmedia-artwork.cgi`

`CarPlayNowPlayingClient` exposes:

- source app and bundle ID;
- title, artist and album;
- playback state;
- elapsed and total duration;
- album artwork when the adapter has completed its JPEG transfer.

An unchanged media sequence is valid, especially while paused, so media liveness does not use navigation-style sequence freshness.

The Media UI now shows CarPlay Now Playing directly. The runtime app target no longer links the Spotify iOS SDK and the project/workflows no longer require a Spotify Client ID, Spotify redirect URI, callback URL scheme, or Spotify app-launch permission. Legacy Spotify source files remain only as excluded historical source so old regression tests/research notes remain inspectable.

Track changes still feed the physical HUD's known native transient Music notification packet. Persistent left/right media widgets remain constrained by the physical HUD firmware's built-in widget capabilities.

## Waze

No speculative Waze client-side force-enable is included. The physical adapter recognizes Waze as a source, but the captured Waze `0x5201` advertises Route Guidance support false and contains no usable maneuver state. U2W v8.6 deliberately preserves the proven v8.5 Route Guidance Identify profile instead of risking Apple/Google reliability with guessed capability fields.

## Compatibility

- Navigation JSON remains the v8.5 schema.
- v90.34 can still navigate against v8.5, but the new Media page requires v8.6 for CarPlay Now Playing.
- Use v8.6 for the intended paired release.
