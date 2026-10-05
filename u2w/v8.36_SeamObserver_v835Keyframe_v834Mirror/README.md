# U2W v8.36 Passive MainVideo Generation-Seam Observer

This is a diagnostic-only layer over the already-installed v8.35/v8.34/v8.31 stack.

It does **not** replace or modify:
- the v8.34 hard-bounded MainVideo mirror,
- the exact v8.31 raw TCP relay,
- the v8.35 keyframe helper,
- Route Guidance / Now Playing / HUD JPEG relay.

The sidecar holds its own read-only fd to `/tmp/u2w_mainvideo_live.h264` and, when the path inode changes, records old/new inode, generation, file sizes, relay fd/offset when visible, SHA-1 of the 256-byte seam sides, and 64-byte hex tails/heads. It also snapshots `/proc/net/unix` and stock-process socket fd metadata for `/var/run/adb-driver` and `/var/run/phonemirror` without connecting or writing to either endpoint.

`u2wvideo-seam-log.cgi` exposes the bounded evidence for the parked diagnostic bundle.
