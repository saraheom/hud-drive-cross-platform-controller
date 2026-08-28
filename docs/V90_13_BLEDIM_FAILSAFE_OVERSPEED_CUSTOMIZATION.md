# v90.13 — BLEDIM fail-safe recovery + overspeed customization

This revision responds to the 2026-08-27 road test where the ELK-BLEDOM center light remained reliable while the BLEDIM2 Door/Dashboard controllers could remain dark after an interrupted synchronized Breath.

## Root cause

The center controller and Door/Dashboard controllers share CoreBluetooth transport, but they do not use the same application protocol. Center uses the Lotus Lantern `7E ... EF` command family; Door and Dashboard use the BEKEN/BLEDIM2 `55 AA ...` FFF1 write-without-response protocol. The road log shows Dashboard timing out during synchronized Breath. Because write-without-response only confirms that CoreBluetooth accepted a write for transmission, the previous code could log a final brightness packet even when the controller firmware did not actually apply it. Door could similarly remain at a transient near-zero raw brightness even without a CoreBluetooth disconnect.

## Reliability policy

1. BLEDIM2 animation writes are paced at 10 Hz (native 0–255 brightness), while Lotus Lantern remains at 20 Hz.
2. If a transient owner (Breath, brightness fade, or overspeed warning) is interrupted by BLE loss, the controller is marked for steady-state recovery.
3. On GATT readiness, a marked controller skips animation rejoin and restores Power ON + normal color + current semantic brightness.
4. Completed BLEDIM2 Breath/fade sequences schedule a three-round spaced reassertion (Power ON / color / brightness, then repeated Power ON / brightness) so a dropped final write self-heals.
5. A real authoritative headlight OFF -> ON epoch still starts a fresh normal headlight animation; only same-epoch interruption recovery is forced steady.
6. Manual power/color/brightness changes cancel stale recovery tasks so recovery never overrides a new user command.

## Overspeed warning

- Warning color is user-selectable; default remains red (`255,0,0`).
- Pulse duration slider is expanded to 0.0–5.0 seconds per cycle. Internally, 0.0 uses a 0.05 s transport-safe minimum to avoid division by zero.
- The first eligible threshold crossing starts a fixed 60 s cooldown. Additional below/above chatter inside that minute is suppressed.
- The existing rule remains `GPS speed > posted speed limit + user offset`, and no valid speed-limit sign means no ambient warning.
