# v90.34.14 — native speed-limit marker + ambient RGB brightness restore

## Scope

This build is a focused follow-up to v90.34.13. It does not alter U2W v8.8, CarPlay route parsing, Apple Maps zero-distance arrival handling, lane guidance, ETA, OSM/Philadelphia speed-limit resolution, HUD Scale/Perspective, or firmware maintenance.

## 1. Original HUDWAY native speed-limit threshold marker

The original HUDWAY Drive 1.4.6 path uses `DisplaySpeedWarningCommandPacket` with command tuple `2 / 9 / 9`. In Automatic mode the threshold equals the detected posted speed limit. The HUD firmware, not the phone, renders the speed-limit threshold indicator.

v90.34.14 keeps that exact packet and adds renderer-change reassertion:

```text
confirmed posted limit
        ↓
DisplaySpeedWarning threshold = posted limit
        ↓
HUD Freeride Simple / Navigation Speedo renderer
        ↓
stock small red threshold arc
```

`HudNavigationController` reports Navigation ON/OFF edges to `AppState`. After a short 150 ms renderer-settle interval, `OriginalSpeedLimitEngine.reassertOriginalSpeedMarker(reason:)` resends the current stock threshold. The Vehicle page's manual **Apply Freeride Widgets** and **Apply Navigation Widgets** actions also reassert the threshold after sending their stock `HudWidgetCommandPacket` profile.

The reassertion preserves the existing confidence boundary:

- confirmed/warning-eligible limit > 0: resend `DisplaySpeedWarning(limit)`;
- no current limit, hidden sign, or display-only/inferred limit: send `DisplaySpeedWarning(0)`.

This avoids arming the native warning/marker from a held or inferred legal-speed value merely for display continuity.

The Vehicle page shows a read-only **Native speed marker** status such as:

```text
55 mph • stock red threshold arc
```

or an explicit Off reason.

### Navigation-side expectation

The decompiled/original profile uses a stock `Speedo` side widget in Navigation, and the app's default Navigation profile remains `Speedo | Navigation | ETA`. The threshold packet is global rather than widget-addressed, so this build makes the same stock threshold available after Navigation activates. Whether firmware 1.1.27 paints the red segment in the compact side `Speedo` is intentionally left for physical verification; no custom phone-side arc is drawn.

## 2. Ambient color → preferred-brightness restore

### Physical behavior being corrected

On the BLEDIM controllers, an RGB write can reset physical brightness to maximum. Previously the app persisted the new RGB color but its logical `lastAppliedBrightness` still reflected the pre-color value, so no subsequent brightness correction was guaranteed.

### Device color path

`setColor` now performs:

```text
persist desired RGB
      ↓
send RGB with existing reliable write helper
      ↓
resolve current steady brightness target
      ↓
restore brightness according to protocol/operation owner
```

The steady target is resolved through the existing `steadyBrightnessTarget(for:)` logic:

- Door + vehicle automation: current Day/Night target from confirmed Center/headlight state;
- otherwise: device preferred brightness.

### BLEDIM2

After a successful RGB write, BLEDIM2 is treated as physically at 100% brightness. The in-memory runtime is updated to 100% and the existing brightness transition engine returns it to the resolved target over a fixed 1.0 second. The preferred brightness value itself is not overwritten.

Example with headlights ON:

```text
Door preferred Day = 70%
Door preferred Night = 25%
headlights = ON
user changes RGB
physical BLEDIM -> 100%
app -> 1.0 s restore -> 25%
```

### Lotus / ELK-BLEDOM

Lotus has independent RGB and brightness packets. Because the same forced-maximum behavior has not been established for that protocol family, v90.34.14 does not synthesize a 100% starting point. It simply reasserts the resolved target after the RGB write. This is idempotent if Lotus preserved brightness.

### Groups and presets

Device presets flow through the device ColorPicker's existing single `setColor` path. Group presets flow through `setGroupColor`, which calls `setColor` for every member. Therefore each member independently resolves its own target after a group RGB change.

A group containing:

```text
Door: Day 70 / Night 25
Dashboard: preferred 40
Center: preferred 35
```

with headlights ON returns to:

```text
Door 25
Dashboard 40
Center 35
```

rather than applying one group brightness to all three.

### Operation ownership

- Active Breath/preparation remains brightness owner. The RGB change is allowed, but no competing post-color fade is started; the Breath's next frames and final target correct brightness.
- Active ambient overspeed warning remains color owner. The newly selected desired RGB is persisted, but the hardware write is deferred. The existing overspeed restore reads the newest saved color and restores to it after the warning completes.
- An ordinary manual brightness fade is superseded by a newer manual RGB action, because the physical RGB write invalidates the fade's prior brightness assumption.

## Verification targets

Physical test priorities:

1. Freeride with a confirmed speed limit: verify the same short red threshold arc seen with the original HUDWAY app.
2. Navigation with left `Speedo`: verify whether firmware paints the same red threshold arc on the compact side speed gauge.
3. Individual BLEDIM color change during Day mode: verify automatic 1 s return to Door Day/preferred target.
4. Individual BLEDIM color change during Night mode: verify automatic 1 s return to Door Night/preferred target.
5. Group color and preset changes: verify each member returns to its own target.
6. Confirm no Breath or ambient overspeed pulse is cancelled by an RGB selection.
