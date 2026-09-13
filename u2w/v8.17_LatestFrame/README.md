# U2W v8.17 — Latest-Frame MainVideo generation guard

Delta update for the validated `2021.03.06.1343` U2W stack with v8.16 MainVideo already installed.

Only `/etc/boa/cgi-bin/u2wvideo-main-stream.cgi` is replaced. Route Guidance, Now Playing, the MainVideo exporter, and the iPhone→U2W→HUD JPEG relay are unchanged.

## Why this exists

The v90.35.3.12 road test showed a distinctive failure: H.264 bytes continued arriving at the iPhone while VideoToolbox stopped producing images. Restarting MainVideo could suddenly produce a large burst of frames. v8.16 already re-opened the rolling MainVideo pathname at EOF, but generation detection was based on file size alone. If the exporter replaced/truncated the file and the new generation had already regrown past the old byte position, v8.16 could resume at the same numeric offset inside a different generation instead of starting at a decoder-safe GOP.

## v8.17 behavior

- A new HTTP client still receives the newest SPS/PPS and newest IDR rather than byte zero.
- Before each EOF reopen, the streamer saves a short fingerprint of the bytes immediately preceding the delivered position.
- After reopening the pathname, it compares that fingerprint at the old offset.
- If the bytes no longer match, the file is a different exporter generation even when its size is larger than the old position. The streamer reboots from that generation's newest SPS/PPS + IDR.
- If the fingerprint matches, it safely continues from the previous position.
- EOF polling is shortened from 100 ms to 60 ms.

This makes the adapter side prefer *current decoder-safe video* over preserving a historical byte offset.

Install requires the v8.16 marker and the existing v8.11 MainVideo exporter marker. The uninstall image restores the exact v8.16 streamer binary from the v90.35.3.12 baseline.
