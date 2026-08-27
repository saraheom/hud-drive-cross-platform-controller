# v90.11 / v90.11.1 — Headlight State, Spotify Recovery, and No-Billing Speed-Limit Testing

## 1. Authoritative headlight state

Dashboard and Center Console share vehicle headlight power, but their CoreBluetooth disconnect callbacks can arrive at different times. The Center/ELK-BLEDOM signal is the event used by the app to send the HUD native auto-brightness ON/OFF command, so v90.11 uses the same edge as the authoritative headlight state for Door day/night automation.

Rapid ON/OFF/ON creates new epochs rather than attempting to resume an interrupted animation. Stale preparation, frames, and final writes from an older epoch are rejected. Door fades are interruptible and retarget from the latest applied runtime brightness.

## 2. Spotify automatic wake

Normal recovery preserves the saved Spotify authorization. HUD Controller first attempts a silent App Remote connection. After repeated failures, it automatically invokes Spotify's wake path without deleting the token. A cooldown prevents wake loops. Reset/Reauthorize remains troubleshooting-only.

## 3. Speed-limit source selector

v90.11.1 removes HERE completely. Three no-billing test paths remain:

### Current

Preserves the decompiled HUDWAY algorithm: 400 m Overpass query, 30 m corridor, bearing + distance score, and the stock posted-limit warning threshold.

### Enhanced OSM

Uses a separate 500 m OSM candidate set with `maxspeed`, `maxspeed:forward`, `maxspeed:backward`, and supported conditional tags. It adds direction-aware speed selection and continuity confirmation before changing roads.

### OSM Trace

Uses the same OpenStreetMap/Overpass road data as Enhanced OSM, but performs a rolling GPS-trace map match locally on the iPhone. Recent samples are weighted more heavily, the newest point must still be plausible on a candidate road, and road switches require both a confidence advantage and repeated evidence. This is intended to reduce false switching among frontage roads, divided highways, parallel streets, and ramps without a commercial API.

The conditional parser is deliberately conservative: common time/day clauses can be applied, while weather-, flashing-light-, school/children-, public-holiday-, vehicle-, and weight-dependent conditions are ignored rather than guessed.

## 4. Overspeed ambient warning

Still parked. The app currently has GPS speed but does not yet receive the vehicle speed that the HUD derives from the connected OBD-II adapter. The red finite-pulse warning will not use GPS speed.
