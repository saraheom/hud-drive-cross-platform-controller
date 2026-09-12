# U2W v8.14 HUD Live Frame Relay

Target: old U2W / Carlinkit `software_version=2021.03.06.1343`, `product_type=U2W`.

This package keeps the existing Carlinkit AP unchanged and extends the successful v8.13 HUD-as-STA topology. The HUD joins the U2W AP using stock HUD mode 6. The iPhone also remains on the U2W AP.

## Data path

- iPhone -> U2W frame ingress: TCP `192.168.50.2:15331`
- frame protocol: four-byte big-endian JPEG length followed by JPEG bytes; persistent connection
- HUD KivicCast discovery: UDP `15320`
- HUD MJPEG stream: TCP `15330`
- output cadence: 5 fps
- accepted JPEG size: 128 bytes through 131072 bytes
- latest frame: `/tmp/u2whud_latest.jpg`
- before the first iPhone frame, the known v8.13 test image is served as a fallback

The package does not alter `wlan0`, hostapd, DHCP, channel, SSID, or password. It does not replace the v8.8 Route Guidance exporter or the v8.11 MainVideo exporter.

## Endpoints

- `http://192.168.50.2/cgi-bin/u2whud-start.cgi`
- `http://192.168.50.2/cgi-bin/u2whud-status.cgi`
- `http://192.168.50.2/cgi-bin/u2whud-stop.cgi`

Use HUD Controller v90.35.3 to start/stop the relay and to send the stock HUD mode-6 STA credentials.
