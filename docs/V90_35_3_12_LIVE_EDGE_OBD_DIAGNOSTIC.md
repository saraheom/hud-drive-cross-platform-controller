# v90.35.3.12 / U2W v8.16

Road-test build focused on two isolated investigations.

- U2W v8.16 replaces only the MainVideo CGI streamer. Each HTTP connection starts from the newest decoder-safe GOP (preceding SPS/PPS + latest IDR) and reopens the live pathname at EOF so exporter file replacement/rotation cannot strand a stale fd. Route/media and the proven HUD JPEG relay are unchanged.
- iOS MainVideo watchdog is relaxed to 10 s / 12 s cooldown and logs whether H.264 bytes are still arriving when decoded frames stall.
- The app can request the HUD firmware's stock `LOG_CATEGORY_OBD` diagnostic ZIP over the existing HUD BLE connection. This reuses `CrushLogRequestDiagnosticPacket` / `CrushLogDiagnosticEventPacket`; no second connection to the OBD dongle is made.
- Existing mode 6 → mode 4 STA persistence test and speed-limit sign customization remain unchanged.
