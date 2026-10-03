# U2W v8.34 — Hard-Bounded MainVideo Mirror + Exact v8.31 Raw Relay

Target: the existing old Carlinkit U2W running **2021.03.06.1343**, with the project's proven v8.11 MainVideo mirror lineage and v8.27.2/v8.15.1 safety markers installed.

## Why this image exists

The 2026-10-02 evening drive validated the v8.33 lossless-rotation direction: MainVideo started without an OEM/reverse-camera transition and decoded continuously for more than five minutes. It also exposed a second defect: v8.33 still rotated only when a later AppleCarPlay write contained an SPS. With long SPS/IDR intervals, the nominal 12 MiB mirror grew to about 48.6 MiB in the field and was able to consume most of the old adapter's RAM-backed `/tmp`. MainVideo, Route Guidance JSON, CGI/status, and the standalone relay then failed together while AppleCarPlay itself remained alive.

v8.34 removes the SPS dependency and makes resource use deterministic.

## Runtime architecture

- **Real AppleCarPlay write path remains first and unmodified.** The mirror observes only bytes that AppleCarPlay already wrote successfully.
- **Hard mirror cap:** 8 MiB per current generation, independent of SPS/IDR cadence.
- **Rotation boundary:** ordinary successful AppleCarPlay write boundary. The complete current write starts the next inode; no H.264 parsing or keyframe search is needed for rotation.
- **Atomic replacement:** the next generation is written to `/tmp/u2w_mainvideo_live.next` and atomically renamed over the live path. A relay already holding the old inode can drain it to EOF before reopening the current path.
- **Write completeness:** mirror writes use write-all semantics; `writev`/`sendmsg` mirror only the byte count actually returned by the real call.
- **Resource guard:** if one write itself exceeds the hard cap, or a bounded next generation cannot be created/written/renamed, v8.34 fails closed for **MainVideo mirror only**. It unlatches the passive mirror rather than allowing `/tmp` to grow without bound. AppleCarPlay, Route Guidance, and Now Playing are not controlled or restarted.
- **Passive FD lifecycle:** the first genuine SPS-bearing outbound FD remains the selector. If that exact selected FD closes, v8.34 merely unlatches it and allows a later genuine SPS-bearing FD to relatch. There is no `/proc` scanning, source forcing, selector mutation, or AppleCarPlay process control.
- **TCP/15332 relay:** exact v8.31 32-KiB raw relay binary (`SHA256 1c19377d...e4a90`).
- **Relay parser/cache:** none.
- **Autostart:** none; the video relay remains explicit/on-demand.

With the normal field write sizes, the current live inode is at most 8 MiB. During an atomic handoff, an old inode held by the relay plus the current inode is normally bounded near 16 MiB, rather than the ~49 MiB current generation observed with v8.33.

## Resource telemetry

`u2wvideo-relay-status.cgi` reports:

- `/tmp` total/used/free KiB;
- current live and temporary-next file sizes;
- hard-cap rotation count;
- successful rotations;
- mirror write failures / partial-write retries;
- MainVideo-only resource-guard trips;
- source FD unlatch / relatch counts.

## Safety boundary

v8.34 does **not**:

- kill, signal, or restart AppleCarPlay;
- kill, signal, or restart ARMiPhoneIAP2;
- change the AppleCarPlay source selector;
- perform aggressive FD/source reacquisition;
- add a GOP/reference-chain/history cache;
- scan historical video generations;
- install a MainVideo boot helper/autostart relay;
- change Route Guidance, Now Playing, or the HUD JPEG relay.

The installer may stop only the standalone custom TCP/15332 relay whose executable path matches `/usr/lib/u2wvideo/u2w_mainvideo_relay`. The normal firmware-updater reboot is required so AppleCarPlay starts with the new passive mirror shim.

## Flash

Upload `U2W_Update_v8.34_HardBoundedMirror_RawRelay.img` through the normal U2W updater as `U2W_Update.img`, allow the updater to complete, and let the adapter reboot normally.

## Expected status

When the on-demand MainVideo relay is active, `u2wvideo-relay-status.cgi` should include:

```text
relay_version=v8.34-hard-bounded-mirror-v831-raw
wire_magic=U2WH2648
raw_buffer_bytes=32768
adapter_h264_parser=NO
adapter_video_cache=NO
relay_autostart=NO
mirror_rotation_policy=hard-8MiB-applecarplay-write-boundary-atomic-inode-swap
```

A healthy field run should show `mirror_hard_cap_rotations` and `mirror_rotation_success` advancing while `mirror_segment_bytes` remains bounded and `tmpfs_free_kb` retains substantial headroom.

## Rollback

`U2W_Update_v8.34_SAFE_ROLLBACK_v8.33.img` restores the exact v8.33 lossless mirror shim and exact v8.31 raw relay/CGIs. It is checksum/version gated. The rollback installer does not signal AppleCarPlay or ARMiPhoneIAP2; the normal updater reboot reloads the restored shim.
