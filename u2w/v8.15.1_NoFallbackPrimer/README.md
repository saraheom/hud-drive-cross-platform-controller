# U2W v8.15.1 — No known-image HUD primer

Requires U2W v8.15 Reliability already installed on the exact target `U2W / 2021.03.06.1343` adapter.

This is a narrow delta over v8.15. It changes only the HUD MJPEG cast relay and its status/start/stop CGI labels.

- The old v8.13 known JPEG is never sent to the HUD.
- On HUD HTTP connection, the relay waits for the first valid baseline 480×240 JPEG from the iPhone.
- That real live iPhone-rendered frame is sent three times to prime the stock HUD decoder, then normal 5 fps live frames continue.
- If live input temporarily disappears or is incompatible, U2W sends nothing and lets the HUD hold its last frame rather than switching to a known fallback image.
- The iPhone v90.35.3.10 app also prewarms one rendered frame before entering mode 6, minimizing first-image latency.

Upload the update image as `U2W_Update.img` through the existing U2W upload CGI, then power-cycle the adapter.
