# v90.35.3.5 — IP soft-connect recovery

Field log `HUD_2026-09-11_23-17-12.log` showed that after the app deliberately cleared the HUD STA network, the HUD repeatedly returned stock status 6 / `Empty network`. Crucially, some of those packets also included `192.168.50.100`, while U2W's ARP table contained both `.100` and `.101`. Therefore status 6 cannot be treated as proof that the Wi-Fi link is down on this firmware.

Changes:
- remove the empty-SSID/password reset from fresh relay Start;
- use a non-destructive mode 4 -> mode 6 transition;
- resend the real `NISSAN68` credentials only;
- treat a valid HUD IPv4 address as a soft-positive STA link;
- trigger KivicCast viewer discovery from either status 1 or status 6 + valid IP;
- allow Retry HUD display to force a viewer kick even when the status packet is ambiguous;
- retain v90.35.3.4 nested-STX BLE frame resynchronization.

U2W remains v8.14.2.
