# v90.34.16 — Time/weather cold-OFF synchronization and speed-gauge probe

## Scope

This is a field-diagnostic release on top of v90.34.15. It does not alter the CarPlay/U2W route-guidance parser, lane normalization, ETA, current-street/turn text, OSM/Philadelphia speed matching, ambient-light automation, OBD transport, display Scale/Perspective, or ADB firmware-maintenance writer.

## 1. Time/weather cold-start behavior

### Physical evidence carried forward

Two independent commutes showed:

1. persisted `showTimeWeather == false`;
2. OFF packets sent during normal rehydration;
3. dashboard profiles rebuilt;
4. another delayed OFF packet sent after those profiles;
5. physical time/weather panel still visible;
6. manual ON followed immediately by OFF hid the panel.

That behavior is more consistent with a stale launcher view/internal-state relationship than with packet ordering alone. Therefore v90.34.16 does not simply add more repeated OFF packets.

### New synchronization policy

After Phase 3 display rehydration, only when the persisted setting is OFF:

```text
existing dashboard/profile rehydration
existing post-dashboard OFF after 300 ms
wait 650 ms
send time/weather ON       # transient synchronization edge
wait 350 ms
send time/weather OFF      # authoritative persisted state
```

The saved setting never changes from OFF. The task rechecks the current setting before both transmitted edge packets; a user change to ON aborts the pending OFF synchronization. HUD disconnect and a new rehydration cancel stale tasks.

Relevant log tag: `TIME/WEATHER`.

## 2. Red speed-marker / gauge probe

### Confirmed protocol pieces

From the recovered Kivic SDK bundled with HUDWAY Drive 1.4.6:

```text
DisplaySpeedCommandPacket
  command=2 p1=9 p2=3
  payload=boolean isSpeedInformationVisible
  default=true

DisplaySpeedWarningCommandPacket
  command=2 p1=9 p2=9
  payload=int32 speedThreshold

DisplaySpeedGaugeCommandPacket
  command=2 p1=9 p2=12
  payload=boolean isSpeedGauge
  default=true

HudSpeedLimitAndToleranceCommandPacket
  command=2 p1=101 p2=2
  payload=int32 limit, int32 tolerance, int32 style
  style 0=round, style 1=square
```

The production Android HUDWAY 1.4.6 path explicitly uses `DisplaySpeedWarning`; it does not explicitly instantiate `DisplaySpeedGauge`. Therefore 9/12 remains diagnostic only until the physical HUD proves its role.

### Original Android speed sequence rechecked

`HwDeviceCommunicationProxy.applyHUDSettings()` calls `setSpeedLimit(...)`, then later `setSpeedTolerance(...)`, with a keepalive between them. In Automatic + TRAVEL mode that can produce:

```text
HudSpeedLimitAndTolerance(limit=0, tolerance=0, style=0)
DisplaySpeedWarning(threshold=current posted limit)
KeepAlive
HudSpeedLimitAndTolerance(limit=last auto limit, tolerance=0, style=0)
```

v90.34.15 A reproduced only the first reset + threshold pair. v90.34.16 D1 adds the later tolerance packet while also explicitly enabling the recovered speed/gauge states.

## 3. Probe definitions

### D0 — Gauge ON + zero threshold

```text
DisplaySpeed(true)
DisplaySpeedGauge(true)
HudSpeedLimitAndTolerance(0,0,style=0)
DisplaySpeedWarning(0)
```

Interpretation: if the small red segment appears near zero, `DisplaySpeedGauge` is a strong candidate for the missing renderer state.

### D1 — Gauge ON + full stock speed chain

```text
DisplaySpeed(true)
DisplaySpeedGauge(true)
HudSpeedLimitAndTolerance(0,0,style=0)
DisplaySpeedWarning(testLimit)
KeepAlive
HudSpeedLimitAndTolerance(testLimit,0,style=0)
```

Interpretation: if D0 shows a zero-position marker and D1 moves it to the selected threshold, the gauge + threshold ownership model is strongly supported.

### D2 — Gauge OFF→ON edge + stock chain

```text
DisplaySpeed(true)
DisplaySpeedGauge(false)
wait 350 ms
D1 sequence
```

Interpretation: useful if D1 alone does nothing but an explicit state edge causes the renderer to update.

### D3 — Exact stock Freeride + gauge edge — PARKED ONLY

```text
HudWidgetCommandPacket: Speedo | Simple | Weather | type 0
Navigation OFF
KeepAlive
wait 250 ms
DisplaySpeed(true)
DisplaySpeedGauge(false)
wait 350 ms
D1 sequence
```

D3 temporarily changes the dashboard and active navigation mode. Use **Restore current HUD** afterward.

## 4. Restore behavior

Restore current HUD:

1. reapplies the user's Freeride and Navigation widget profiles;
2. restores the actual Navigation/Freeride operating mode;
3. reapplies the saved time/weather state;
4. sends `DisplaySpeed(true)` and returns the experimental 9/12 gauge boolean to OFF;
5. restores the current production square speed-limit sign and original warning threshold, or clears them when no live limit exists.

No selected source, cached road result, or UserDefaults speed setting is changed by the probes.

## 5. Suggested physical test order

Use the HUD parked for the probe controls, especially D3.

1. Start with no active route and note whether the current custom app shows no red arc.
2. Tap **D0** and check specifically for a tiny red segment near zero.
3. Set the test threshold to 25 mph and tap **D1**; check whether the segment moves to ~25.
4. If D1 does nothing, try **D2**.
5. Try **D3** last, parked, to eliminate dashboard-profile differences.
6. Tap **Restore current HUD** when finished.

Export the HUD Controller log after testing. `SPEED MARKER PROBE`, `TX`, and `TIME/WEATHER` lines will identify the exact sequence used.
