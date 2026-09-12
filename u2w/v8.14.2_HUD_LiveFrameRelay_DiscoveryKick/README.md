# U2W v8.14.2 — HUD Live Frame Relay discovery stability

Pairs with HUD Controller v90.35.3.2. This revision keeps the validated iPhone -> U2W -> HUD relay architecture but removes two restart races observed in field testing.

- `u2whud-start.cgi` is idempotent: repeated Start calls reuse healthy ingress/discovery/cast daemons instead of killing them.
- The latest uploaded JPEG is preserved across repeated Start.
- UDP 15320 discovery stays persistent and responds to any datagram arriving on the dedicated KivicCast discovery port, while logging whether the canonical `KVMJPEG/1.0` signature was present.
- U2W AP/hostapd/DHCP are unchanged.
- v8.8 route/lane/Now Playing exporter and v8.11 MainVideo exporter are preserved.

The paired app now waits for stock STA status=1 and re-primes mode 6 after association so the HUD viewer performs discovery on the established 192.168.50.x interface.
