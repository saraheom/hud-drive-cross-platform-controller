# v90.29 — HUD-gated ambient sync + original Freeride active-mode restore

## Why this revision exists

The 2026-09-02 afternoon field logs clarified two independent issues.

First, the center Freeride RPM/bar presentation disappeared during the drive, not because the app was relaunched. The first log contains a mid-drive HUD/session rehydration. During rehydration the app correctly configures both dashboard profiles with the original `HudWidgetCommandPacket` format, but the iOS 26 test flavor had no ScreenCaptureKit navigation lifecycle to explicitly restore `Navigation OFF` afterward. Relaunching the same app repeated that profile-only sequence, while connecting the stock HUDWAY app restored the firmware's normal Freeride center presentation.

Second, OBD connection events can arrive minutes after the HUD itself is already connected. OBD is therefore a poor automatic-animation permission signal even though it remains useful vehicle telemetry.

## Original HUDWAY dashboard semantics

The previously audited JADX behavior is retained:

- `HudWidgetCommandPacket`: command 2, p1 111, p2 0.
- payload: Java `writeUTF(left)`, `writeUTF(center)`, `writeUTF(right)`, then int32 profile type.
- type 0 = Freeride; the center token is `Simple`.
- type 1 = Navigation; the center token is `Navigation`.
- left/right values are original `SideWidget` `dashName` strings.

Dashboard profile configuration is separate from the HUD's active navigation state (`navigationState`, command 2 / p1 101 / p2 0). v90.29 therefore continues configuring both type-0 and type-1 profiles during HUD rehydration, then explicitly restores the active mode:

- navigation inactive -> `Navigation OFF` -> Freeride active;
- navigation active -> `Navigation ON`; the active navigation source owns maneuver re-delivery.

There is no 20-second Freeride watchdog. The RPM/orange center presentation remains firmware-managed; the app does not fabricate phone-side RPM or draw a replacement bar.

The unused **Minimize widgets** UI remains removed. Its stored compatibility property is retained.

## Ambient automatic-animation gate

v90.29 replaces v90.27/v90.28's OBD gate with the HUD transport session.

### Before HUD connection

Courtesy lights may power and establish GATT. They remain steady and do not automatically Breath.

### HUD transport connects

One startup opportunity is armed:

1. require configured/enabled Center + Door + Dashboard;
2. wait up to 10 seconds for all three to be GATT/boot-settle ready;
3. release exactly one common T0 only for a full 3/3 cohort;
4. if a member is missing, skip the startup Breath—no partial or late catch-up.

### Later headlight ON while HUD remains connected

Only newly powered members animate. Center and Dashboard remain a paired headlight-fed cohort so Center cannot begin while Dashboard is still in BLEDIM settle. An already-active Door remains untouched.

### HUD disconnect

The animation gate closes and the next HUD transport session is re-armed. OBD connection/disconnection no longer arms, cancels, or releases ambient Breath cohorts; it remains diagnostic/corroborating state only.

Manual Preview is unchanged.

## Speed-limit behavior retained from v90.28

- bounded same-road display cache;
- completed-turn takeover and corridor consensus;
- pending same-displayed-mph confirmation suppresses the one-sample stale-sign blank while warning freshness remains disabled;
- Philadelphia Street Centerline query uses WGS84 point + 650 m server-side distance;
- diagnostics report raw, speed-bearing, geometry-bearing, and parsed feature counts.
