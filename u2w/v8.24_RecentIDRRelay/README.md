# U2W v8.24 — Bounded Recent-IDR MainVideo Relay

v8.24 keeps the proven v8.11 AppleCarPlay MainVideo mirror and dedicated TCP/15332 architecture, but closes the startup race observed on 2026-09-19: a valid IDR could arrive milliseconds before the iPhone connected, causing v8.23 to wait indefinitely for another keyframe.

Path:

`AppleCarPlay → v8.11 /tmp/u2w_mainvideo_live.h264 → v8.24 relay TCP/15332 → iPhone sanitizer/VideoToolbox`

The relay:

- never opens or modifies AppleCarPlay file descriptors;
- never sends long-lived video through Boa/CGI;
- uses wire magic `U2WH2643` followed by `[u32BE length][NAL]` records;
- preserves H.264 parser continuity across normal v8.11 mirror rollovers;
- retains validated SPS/PPS plus a **bounded 4 MiB recent chain beginning at the latest valid IDR**;
- immediately bootstraps a newly connected iPhone from that recent anchor when available;
- otherwise waits for the next naturally arriving valid IDR;
- invalidates the recent anchor rather than growing beyond 4 MiB, avoiding the unsafe 17–20 MiB v8.22 history burst;
- forwards live NALs at their natural source rate after bootstrap.

`u2wvideo-relay-status.cgi` exposes recent-anchor readiness/size, anchor resets/overflows, recent bootstraps, source progress, client state, send failures, and the relay log tail.

The uninstall image restores the v8.23 relay and the known-good v8.15.1 HUD cast components.
