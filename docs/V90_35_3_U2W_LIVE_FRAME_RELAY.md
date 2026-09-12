# v90.35.3 / U2W v8.14 — live frame relay

## Proven prerequisite

The v8.13 home test physically rendered the known U2W test image on the HUD while the iPhone remained connected to the same `NISSAN68` Carlinkit AP. This proves HUD mode 6, U2W KivicCast discovery, and U2W-hosted MJPEG all work together.

## Live relay topology

1. U2W v8.14 starts two lightweight ARM servers.
2. TCP 15331 accepts a persistent iPhone frame stream: `[u32 big-endian JPEG length][JPEG bytes]`.
3. The latest valid JPEG is atomically stored in `/tmp/u2whud_latest.jpg`.
4. UDP 15320 answers the HUD's `KVMJPEG/1.0` discovery.
5. TCP 15330 serves an MJPEG stream at 5 fps, always reading the most recent JPEG.
6. Until the first live JPEG arrives, the known static bridge-test image is served.

## iOS behavior

- starts the v8.14 relay through `u2whud-start.cgi`;
- opens persistent TCP/15331 through `U2WHUDFrameRelayClient`;
- renders the existing `HudMapModeFrameRenderer` output every 200 ms;
- keeps `U2WMainVideoClient`, Route Guidance and Now Playing active;
- sends stock HUD mode 6 and Wi-Fi STA credentials over BLE;
- treats stock Wi-Fi status 1 as connected even when the address field is blank;
- stopping the relay clears STA credentials, restores HUD mode 4, and stops the U2W relay servers.

The legacy mode-5 iPhone→HUD AP path remains available only for comparison.
