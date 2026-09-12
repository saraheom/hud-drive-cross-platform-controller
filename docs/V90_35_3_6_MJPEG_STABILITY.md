# v90.35.3.6 — MJPEG stability

Field result before this revision:

- HUD STA status reached `status=1 / connected / 192.168.50.100`.
- U2W saw repeated UDP discovery and replied.
- U2W logged a HUD MJPEG TCP client at least once.
- The app immediately sent another mode-6 viewer kick because it sampled the TCP state before the HTTP stream became established.

v90.35.3.6 suppresses that automatic second mode-6 kick once discovery or an HTTP client has already been observed. It waits five seconds for the HTTP/MJPEG session to settle. Only a complete absence of discovery triggers an automatic retry. Manual Retry is rate-limited.

U2W v8.14.3 adds SIGPIPE-safe writes, SO_REUSEADDR, HEAD-probe handling, known-good decoder priming frames, live-JPEG compatibility checking, and additional stream diagnostics.
