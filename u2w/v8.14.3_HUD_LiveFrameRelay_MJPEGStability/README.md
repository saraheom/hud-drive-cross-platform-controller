# U2W v8.14.3 — HUD MJPEG relay stability

Pairs with HUD Controller v90.35.3.6. This revision keeps the proven HUD-as-STA topology and fixes the HTTP/MJPEG stage observed after Wi-Fi and UDP discovery succeeded.

- TCP/15330 writes use `MSG_NOSIGNAL`, so a HUD probe/reconnect cannot kill the relay with SIGPIPE.
- `SO_REUSEADDR` reduces bind races after restarts.
- HEAD probes are answered without entering the infinite stream loop.
- Each GET is primed with three copies of the exact known-good v8.13 480x240 JPEG before switching to the live iPhone frame.
- Live frames are served only when they are baseline SOF0 JPEG at 480x240; otherwise the known-good frame remains visible and status logs the incompatibility.
- Status exposes whether a HUD HTTP client was seen, fallback frame was sent, live frame was sent, and whether a send failure occurred.
- U2W AP/hostapd/DHCP, v8.8 route/lane/media, and v8.11 MainVideo are unchanged.
