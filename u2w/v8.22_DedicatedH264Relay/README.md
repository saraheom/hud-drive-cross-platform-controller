# U2W v8.22 — Dedicated H.264 Relay + HUD Cast Watchdog

Target: Carlinkit U2W `2021.03.06.1343`.

This release retires the v8.21 long-lived MainVideo CGI/file-cache data path. The stable v8.11 MainVideo exporter remains untouched. A standalone ARM daemon tails `/tmp/u2w_mainvideo_live.h264` and serves one iPhone client directly on TCP/15332 using an explicit framed-NAL protocol:

`U2WH2641` + repeated `[u32 big-endian NAL length][NAL bytes]`.

The relay keeps the latest decoder-safe GOP in its own process memory so source-file rotations cannot truncate a cache underneath an active reader. A startup catch-up pass reaches the current live edge before bootstrapping a client, preventing a daemon restart from rapidly replaying an old route as if it were live. The GOP cache is bounded at 20 MiB. If it overflows during an unusually long GOP, the active stream continues; a new client waits for the next IDR rather than consuming unbounded adapter memory.

The final HUD MJPEG sender on TCP/15330 is also hardened with socket send/receive timeouts. If the physical HUD stops consuming while leaving TCP open, the sender closes that stalled viewer rather than blocking indefinitely on one old frame.

## Safety scope

- Does **not** inject into, hook, restart, or replace `AppleCarPlay`.
- Does **not** change the v8.11 MainVideo exporter.
- Does **not** change Route Guidance or Now Playing exporters.
- Does **not** carry continuous MainVideo through Boa/CGI.
- Only lightweight start/status CGI endpoints remain.
- Installer explicitly terminates orphaned legacy `u2w_mainvideo_streamer` CGI processes from v8.20/v8.21.
- Uninstall restores the exact bundled v8.15.1 HUD cast relay and best-effort restarts the pre-v8.22 v8.21 cache helper.

## New endpoints

- `http://192.168.50.2/cgi-bin/u2wvideo-relay-start.cgi`
- `http://192.168.50.2/cgi-bin/u2wvideo-relay-status.cgi`
- MainVideo data plane: `192.168.50.2:15332`

The status endpoint reports relay process state, startup scan, GOP readiness/overflow, client session/bootstrap counters, legacy CGI process counts, basic memory state, and recent relay log lines.
