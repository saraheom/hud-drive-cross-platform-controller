# U2W v8.20 — Validated-GOP MainVideo bootstrap

Delta update for the validated U2W 2021.03.06.1343 stack. It changes only `/etc/boa/cgi-bin/u2wvideo-main-stream.cgi`; the v8.11 MainVideo exporter, Route Guidance, Now Playing, and HUD JPEG relay remain unchanged.

## Why

The 2026-09-17 commute showed that raw MainVideo bytes and valid P-slices continued after an isolated iPhone VideoToolbox decode error. The image returned only when navigation ended and CarPlay emitted a real SPS/PPS/IDR sequence. In addition to the iPhone decoder fix in HUD v90.35.3.18, v8.20 makes HTTP/reconnect bootstrap selection more conservative.

## v8.20 behavior

- retains the v8.17 generation fingerprint guard and live-edge behavior;
- validates candidate SPS/PPS/IDR NALs before choosing the newest GOP;
- rejects impossible forbidden bits, implausible SPS/PPS sizes, and unknown SPS profile bytes;
- requires SPS -> PPS -> IDR ordering within generous CarPlay-like proximity bounds;
- seeds each new/reseeded HTTP client with only the validated parameter sets followed by the validated newest IDR;
- does **not** patch or reselect AppleCarPlay file descriptors.

The uninstall image restores the exact v8.17 streamer binary.
