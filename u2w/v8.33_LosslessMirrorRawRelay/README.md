# U2W v8.33 — Lossless MainVideo Mirror + Exact v8.31 Raw Relay

Target: the existing old Carlinkit U2W running **2021.03.06.1343**, with the project's proven v8.11 MainVideo mirror and v8.27.2/v8.15.1 safety markers already installed.

## Why this image exists

The Oct. 2 drive isolated a byte-loss defect in the exact v8.11 passive MainVideo mirror. When the rolling file exceeded 12 MiB and a successful AppleCarPlay write contained an SPS later in the same buffer, v8.11 truncated the live mirror and copied only from the first Annex-B start code. Any bytes before that SPS—including the continuation/tail of the previous reference NAL—were omitted from the mirror even though AppleCarPlay itself had written them successfully.

One missing reference picture is sufficient to produce the observed `frame_num` discontinuity and VideoToolbox `codecBadDataErr (-8969)` cascade until another real IDR appears.

v8.33 fixes the mirror copy rather than adding another GOP/checkpoint recovery layer.

## Runtime architecture

- **AppleCarPlay real write path:** unchanged; the real `write`/`send`/`writev`/`sendmsg` completes first.
- **Passive mirror:** v8.11 source-selection behavior retained, with lossless write/rotation fixes only.
- **Rotation:** the complete successful AppleCarPlay write is written to a temporary next-generation inode and atomically renamed over the live path. A relay holding the old inode can drain it to EOF before reopening the new generation.
- **Failure policy:** if the atomic next-generation write/rename fails, the entire buffer is appended to the old file. The mirror may temporarily exceed 12 MiB rather than drop a stream byte.
- **Partial mirror writes:** retried until complete (`write-all`).
- **Vectored writes:** mirror only the byte count actually returned by the real `writev`/`sendmsg` call.
- **TCP/15332 relay:** exact field-proven v8.31 32-KiB raw relay binary.
- **Adapter H.264 parser/cache:** none in the relay.
- **Autostart:** none; relay remains explicit/on-demand.

## Safety boundary

v8.33 does **not**:

- kill, signal, or restart AppleCarPlay;
- kill, signal, or restart ARMiPhoneIAP2;
- change the AppleCarPlay source selector;
- add FD/source reacquisition;
- add a GOP/reference-chain cache;
- add a boot helper/autostart relay;
- change Route Guidance or Now Playing;
- change the HUD JPEG relay.

The installer stops only the standalone custom TCP/15332 relay before replacing its files. The normal firmware-updater reboot is required so AppleCarPlay starts with the new passive mirror shim.

## Flash

Upload `U2W_Update_v8.33_LosslessMirror_RawRelay.img` through the normal U2W updater as `U2W_Update.img`, allow the updater to complete, and let the adapter reboot normally.

## Expected status

When the on-demand MainVideo relay is active, `u2wvideo-relay-status.cgi` reports:

- `relay_version=v8.33-lossless-mirror-v831-raw`
- `adapter_h264_parser=NONE`
- `adapter_video_cache=NONE`
- `autostart=NO`

The mirror status also exposes:

- generation;
- rotation attempts/successes;
- fallback appends;
- prefix bytes preserved at rotations;
- partial-write retries;
- mirror-write failures.

A successful field validation should show rotations increasing while iPhone decoded frames continue advancing without a new `-8969`/reference-loss event.

## Rollback

`U2W_Update_v8.33_SAFE_ROLLBACK_v8.32.img` restores the exact v8.11 mirror shim and the exact v8.32 relay/CGIs. It is checksum-gated and does not signal AppleCarPlay or ARMiPhoneIAP2; the normal updater reboot reloads the restored shim.
