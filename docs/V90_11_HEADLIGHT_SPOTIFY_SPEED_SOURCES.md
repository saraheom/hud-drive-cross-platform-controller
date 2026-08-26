# v90.11 — Headlight State, Spotify Recovery, and Speed-Limit Source Test Matrix

## 1. Authoritative headlight state

Dashboard and Center Console share vehicle headlight power, but their CoreBluetooth disconnect
callbacks can arrive at different times. The Center/ELK-BLEDOM signal is already the event used by
the app to send the HUD's native auto-brightness ON/OFF command. v90.11 therefore uses this same
edge as the authoritative headlight state for Door day/night automation.

### ON

- Create a new headlight epoch.
- Cancel stale headlight animation/preparation state.
- Start Door -> Night brightness immediately when vehicle automation is active.
- Any already controllable Dashboard/Center light is re-bootstrapped for the new epoch.
- A light whose GATT control characteristic becomes ready later joins only the current epoch.

### OFF

- Invalidate the current headlight epoch immediately.
- Cancel Dashboard/Center Breath preparation and remove them from the active Breath session.
- Skip any stale final-brightness write that belongs to the old epoch.
- Start Door -> Day brightness on the same event that sends HUD auto-brightness OFF.

Rapid ON/OFF/ON therefore creates two distinct epochs rather than trying to resume the interrupted
animation.

## 2. Spotify automatic wake

Normal recovery never deletes the saved Spotify authorization. HUD Controller first tries a silent
App Remote connection. After two consecutive failures, it automatically calls Spotify's wake path
with the existing authorization. A 45-second cooldown prevents wake loops. Returning to HUD
Controller or receiving a Spotify callback rebuilds the App Remote and reconnects automatically.

The manual Reset/Reauthorize command is reserved for revoked/invalid authorization.

## 3. Speed-limit source selector

### Current

Preserves the existing decompiled HUDWAY algorithm exactly: 400 m Overpass query, 30 m corridor,
bearing + distance score, and the stock posted-limit warning threshold.

### Enhanced OSM

A separate experimental path. It requests `maxspeed`, `maxspeed:forward`, and
`maxspeed:backward`, evaluates direction of travel, uses a 45 m candidate radius, gives continuity
preference to the currently matched road, and requires one confirmation sample before switching to
a different road/link. It intentionally does not replace Current unless selected.

### HERE

Uses a rolling GPS trace and HERE Route Matching v8 with `APPLICABLE_SPEED_LIMIT(*)`. The API key is
entered in Vehicle -> Speed + Speed Limit and stored in iPhone Keychain. The repository contains no
HERE credential. Requests are throttled and stale responses are discarded if the user switches
source while a request is in flight.

## 4. Overspeed ambient warning

Not implemented in v90.11. The app currently owns GPS speed but does not receive the vehicle speed
that the HUD derives from the connected OBD-II adapter. The red finite-pulse warning remains parked
until that OBD/HUD speed can be read directly.
