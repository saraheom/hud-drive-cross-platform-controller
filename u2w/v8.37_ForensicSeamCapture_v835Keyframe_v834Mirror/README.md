# U2W v8.37 Forensic MainVideo Seam Capture

v8.37 is a **diagnostic-only sidecar** layered over the already-installed v8.36/v8.35/v8.34/v8.31 stack. Its purpose is to determine whether the H.264 reference discontinuity observed in the October 5 drive is introduced at a MainVideo generation boundary, in the raw relay path, or later on the iPhone.

It does **not** replace or modify the v8.34 hard-bounded mirror, the exact v8.31 raw TCP relay, or the v8.35 helper. It does not signal/restart AppleCarPlay, ARMiPhoneIAP2, fakeiOSDevice, Route Guidance, Now Playing, or the relay process.

At each `/tmp/u2w_mainvideo_live.h264` inode transition, the observer keeps its old read-only file descriptor open long enough to save a binary 4096-byte old-tail sample and a binary 4096-byte new-head sample. It records SHA-1 fingerprints, generation/inode/size metadata, a snapshot of every visible relay fd/position, the mirror status, and passive `/proc` IPC topology. The newest 128 seam groups are retained.

Parked collection endpoints:
- `u2wvideo-forensic-status.cgi` — evidence counts and safety flags.
- `u2wvideo-seam-log.cgi` — bounded text seam summary.
- `u2wvideo-forensic-bundle.cgi` — `.tar.gz` containing seam metadata and binary boundary samples.

The install script refuses to proceed unless the exact v8.34 mirror SHA-1 is `b982322ee65fd45405ab40f98512dbd76450976b` and the exact v8.31 relay SHA-1 is `b3964792342f9bc5ad22eaeb70eaf84ec04562f6`.

Run `python3 validate_forensic_rotation.py` before packaging to exercise 71 deterministic seam captures, deliberate corruption detection, and a 143-rotation retention pass.
