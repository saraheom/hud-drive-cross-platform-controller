# U2W v8.38 — Read-Only Startup Bootstrap Snapshot

This release adds a passive startup-history sidecar while leaving the proven live transport unchanged:

- exact v8.34 hard-bounded mirror binary: unchanged;
- exact v8.31 raw TCP/15332 relay binary: unchanged;
- v8.35 bounded keyframe helper: unchanged;
- v8.37 forensic seam capture: retained.

## Startup-history behavior

A passive observer now starts at adapter boot and waits for `/tmp/u2w_mainvideo_live.h264`. It never starts TCP/15332 and never signals/restarts AppleCarPlay or Route Guidance. Across the mirror's normal atomic inode rotation it keeps a read-only copy of the immediately previous complete mirror generation. Two read-only CGI endpoints expose:

- `/cgi-bin/u2wvideo-bootstrap-previous.cgi`
- `/cgi-bin/u2wvideo-bootstrap-current.cgi`

The current endpoint first copies the live mirror to a private temporary file and rejects the copy if the mirror inode/generation rotates during capture. The previous endpoint validates its private copy against the observer-recorded SHA/generation metadata. H.264 parsing/validation remains entirely on the iPhone. The app attaches to the unchanged v8.31 relay **first** and buffers its live-edge bytes while snapshots transfer. It proves an exact byte overlap between the end of the current snapshot and that buffered TCP stream, and prepends the previous snapshot only when metadata proves `previous.next_generation == current.generation`. If overlap or generation coherence cannot be proven, that unsafe history is skipped rather than risking a discontinuous bootstrap.

If the snapshots contain no usable SPS/PPS/IDR, the app safely falls back to the existing WAITING_LIVE_IDR behavior; no CarPlay process-control fallback is attempted.

## Safety boundary

The v8.38 sidecar does **not**:

- replace or patch the v8.34 mirror;
- replace or patch the v8.31 relay;
- change TCP/15332 framing;
- parse H.264 on the adapter;
- write/truncate/rename the live H.264 mirror;
- signal, kill, restart, or inject IPC into AppleCarPlay/ARMiPhoneIAP2;
- change Route Guidance.

The install image verifies exact v8.34/v8.31 hashes before installing. The rollback image restores the v8.37 observer/CGIs and removes the v8.38 passive boot hook/endpoints.
