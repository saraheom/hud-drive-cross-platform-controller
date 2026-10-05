# v90.35.3.24.24 existing-repo overlay

Apply this ZIP at the root of the existing v24.23 repository, preserving paths and overwriting matching files.

Paired field diagnostic: U2W v8.36 Passive Seam Observer. The v8.36 image must be flashed separately; it leaves the exact v8.34 mirror, exact v8.31 relay, and installed v8.35 keyframe helper unchanged.

Primary changes:
- passive generation-seam telemetry bundled into Live Map diagnostics;
- known-invalid v8.35 datagram keyframe injection deferred while v8.36 is active;
- automatic single-client OBD ownership handoff for physical Map Mode;
- direct ELM327 `01 0D` speed at 5 Hz with GPS fallback;
- separate customizable Map Mode Speed Warning card.
