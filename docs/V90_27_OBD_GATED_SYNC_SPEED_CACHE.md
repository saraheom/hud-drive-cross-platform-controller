# v90.27 — OBD-gated strict ambient sync + bounded same-road speed cache

## Ambient animation state machine

v90.27 simplifies automatic animation ownership.

### OBD disconnected

Light connections may occur because of courtesy lighting, but automatic Breath
is held. GATT readiness alone is never permission to animate.

### OBD connects

OBD connection is treated as the ambient animation ignition edge. The app opens
one strict startup cohort containing the configured/enabled Center, Door, and
Dashboard roles. All three must become controllable and finish their normal
preparation/boot-settle work within the 10 s startup window. If all three are
ready, they start on one common T0. If any member is missing, the startup Breath
is skipped entirely; there is no partial or late catch-up animation.

### Later headlight ON while OBD remains connected

Only newly powered lights animate. Center and Dashboard are treated as the
headlight-fed synchronization pair: if either is newly joining, the other is
enrolled even if its CoreBluetooth/GATT callback arrives slightly later. An
already-active Door is not recruited. Every enrolled member must be ready before
T0; otherwise that transition's Breath is skipped rather than split.

Manual Preview is unchanged and remains an explicit force-animation tool.

## Speed-limit continuity

v90.27 retains v90.26 completed-turn takeover, same-road successor handoff,
pending same-limit continuity, and unanimous OSM corridor consensus.

It adds a bounded display-only cache for a speed limit that was freshly
established on the current normalized road identity. During a short OSM/cache
hole, the displayed value may remain if the road identity is unchanged and GPS
course/distance/time remain compatible. The cache is limited to 90 s, 1.2 km,
and 35 degrees of course change when no OSM candidate is available. A live
same-road untagged OSM match can also refresh support for the cache.

Cached holds never refresh warning freshness. If the cache becomes active, the
native speed-warning threshold is disabled. A completed turn onto a different
road invalidates the cached road limit immediately.

## Philadelphia diagnostics

The Street Centerline fallback now logs four separate counts on each successful
query:

- raw ArcGIS features returned
- features containing a valid speed value
- features containing geometry
- final parsed speed segments

This makes the next drive log sufficient to determine whether the current zero
match problem comes from the ArcGIS spatial query, missing speed attributes,
geometry decoding, or downstream matching.
