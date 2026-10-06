# U2W v8.27 — Lightweight Live-Edge IDR Relay

v8.27 replaces the v8.26 persistent-GOP cache with a deliberately smaller and safer relay.

- Proven v8.11 AppleCarPlay MainVideo capture remains byte-for-byte unchanged.
- No historical GOP scan or replay.
- No `/tmp/u2w_mainvideo_validated_gop.cache`; install deletes the old v8.26 cache.
- Relay opens the v8.11 mirror at its current live edge and validates only newly arriving 800×480 H.264.
- SPS/PPS/parser state survives ordinary v8.11 rolling-file generations.
- A new/recovering iPhone waits on the same TCP connection for the next validated live IDR.
- Zero-length framed heartbeats keep transport liveness distinct from decoder bootstrap.
- One-second socket send timeout prevents a slow iPhone from blocking the relay.
- `u2wvideo-relay-status.cgi` is intentionally lightweight (no `netstat`, no long log tail).
- Safe rollback image restores v8.23 live-IDR relay rather than the heavier v8.26 cache design.

This may trade cold-start latency for reliability: a cold/recovered decoder can wait until the next natural CarPlay IDR. The iOS app prewarms the relay/decoder for the car session so navigation start itself does not normally create a new bootstrap dependency.
