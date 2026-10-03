# U2W v8.35 — bounded native keyframe request over unchanged v8.34 mirror

This is an incremental package for the exact v8.34 hard-bounded mirror baseline.
It does **not** replace the MainVideo mirror shim or the exact v8.31 raw TCP relay.
It adds one freestanding ARM helper and one CGI endpoint for a single Carlinkit
`RequestKeyFrame` (`type 0x0C`, zero payload) datagram, plus status telemetry.

Safety boundaries:
- adapter-side 8-second request cooldown;
- no AppleCarPlay or ARMiPhoneIAP2 signal/restart;
- no MainVideo TCP reconnect;
- no source-FD reacquisition;
- no Route Guidance/Now Playing/HUD cast changes;
- v8.34 mirror and v8.31 raw relay remain byte-identical.

The local Unix-datagram injection route is field-validation code: `/var/run/adb-driver`
is tried once, then `/var/run/phonemirror` once only if the primary send fails.
