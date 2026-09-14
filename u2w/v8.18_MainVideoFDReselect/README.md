# U2W v8.18 — MainVideo FD reselection

This update keeps the v8.17 live-edge HTTP streamer and replaces only the v8.11 `AppleCarPlay` MainVideo LD_PRELOAD exporter shim plus its status CGI.

## Why this exists

Field logs from v90.35.3.13.3 showed a valid 800×480 H.264 bootstrap and several live frames, followed by multi-kilobyte false SPS/PPS candidates while the exporter continued reporting writes on the same numeric `main_fd`. The most consistent failure mode is descriptor lifetime/reuse inside `AppleCarPlay`: the fd initially carrying MainVideo can be closed or repurposed while v8.11 keeps trusting the old integer.

v8.18 therefore treats an fd as MainVideo only after an H.264 bootstrap is observed and continuously revalidates that selection.

## Selection policy

The preload shim observes outbound `write`, `send`, `writev`, and `sendmsg` data without changing the stock bytes. It:

- starts a candidate only from a plausible Annex-B SPS;
- promotes only after SPS → PPS → IDR evidence;
- hooks `close()` and immediately invalidates the selected/candidate fd when it is closed;
- invalidates a selected fd after repeated implausible oversized parameter sets or 2 MiB without plausible H.264;
- can move to another proven fd if a new complete SPS/PPS/IDR bootstrap appears after the selected stream has gone stale;
- keeps the existing ~12 MiB generation rotation behavior;
- exposes fd promotion/switch/invalidation counters in `u2wvideo-status.cgi`.

The HTTP MainVideo streamer remains the installed **v8.17 LatestFrame generation-guard** implementation. Route Guidance, media export, and the HUD JPEG relay are not replaced by this image.

## Prerequisites and target gate

The installer requires:

- `software_version=2021.03.06.1343`
- `product_type=U2W`
- `/etc/u2w_mainvideo_v8_11.marker`
- `/etc/u2w_v8_17_latest_frame.marker`
- the active MainVideo shim to match either the exact v8.11 shim or this v8.18 shim

If any gate fails, installation aborts rather than writing an unexpected device.

## Installation

Upload `U2W_Update_v8.18_MainVideoFDReselect.img` through the same U2W firmware-upload endpoint used for prior custom images. **After the upload has completed, fully remove power from the Carlinkit adapter and reconnect it.** A Wi-Fi reconnect alone is insufficient because the new shim must be loaded into a newly started `AppleCarPlay` process.

After the power cycle, `http://192.168.50.2/cgi-bin/u2wvideo-status.cgi` should begin with:

```text
U2W Main CarPlay Video Exporter v8.18 fd-reselection
fd_reselect=INSTALLED
```

Once CarPlay/MainVideo is active, useful counters include `main_fd`, `candidate_fd`, `fd_promotions`, `fd_switches`, `fd_invalidations`, `fd_close_invalidations`, `bad_parameter_sets`, and `main_bytes_since_valid_h264`.

## Rollback

`U2W_Update_v8.18_MainVideoFDReselect_UNINSTALL.img` restores the exact v8.11 MainVideo shim and v8.11 status CGI. It intentionally leaves the v8.17 HTTP streamer installed. A full adapter power cycle is also required after rollback.

## Checksums

See `U2W_v8.18_SHA256SUMS.txt`.
