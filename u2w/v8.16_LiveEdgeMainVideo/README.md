# U2W v8.16 — MainVideo Live Edge

Delta update for the validated 2021.03.06.1343 U2W + v8.15 Reliability + v8.15.1 No Known-Image Primer stack.

Only `/etc/boa/cgi-bin/u2wvideo-main-stream.cgi` is replaced. Route/media shims and the HUD JPEG relay are not modified.

The v8.16 streamer:
- scans the current rolling Annex-B segment for the newest IDR and the SPS/PPS that preceded it;
- sends those parameter sets, then streams from the latest IDR instead of byte zero;
- closes/reopens the live pathname at EOF so exporter file replacement/rotation cannot leave it attached to a stale inode;
- re-bootstraps from the newest decoder-safe GOP after a generation rollover.

Install requires markers for v8.15 Reliability, v8.15.1 primer, and v8.11 MainVideo exporter. The uninstall image restores the exact v8.15 rotation-safe streamer.
