# v90.26 — Ambient Synchronization and New-Road Speed Acquisition

## Field symptoms addressed

The 2026-09-01 field log showed two repeatable automatic ambient failures that did not occur in manual Preview: Center could begin a synchronized Breath while Dashboard was still inside its 1.5-second BLEDIM boot-settle, and the one-time engine-start coordinator could consume the startup exception while Center/Dashboard were temporarily absent during crank. It also showed long initial speed-limit acquisition after completed turns, especially onto North 33rd Street and Martin Luther King Junior Drive.

## Ambient changes

- Normal headlight/courtesy cohorts still contain only newly joining lights.
- Physical membership no longer treats a long-lived pending CoreBluetooth connect request as proof that an unpowered light exists. A connecting peripheral needs recent radio evidence; an actually connected controller always qualifies.
- After the 2.0-second discovery floor, the ordinary 4.5-second barrier may extend to a 7.0-second hard cap **only while an already-admitted live controller is actively completing connection/GATT/boot preparation**. This prevents T0 from firing a few hundred milliseconds before Dashboard's known boot settle completes.
- Initial engine OFF→ON keeps the startup exception alive through a 15-second post-crank reacquisition window, bounded at 16 seconds. If all enabled vehicle roles return, become controllable, and BLEDIM has remained GATT-ready for 1.5 seconds, Center + Door + Dashboard use the existing full-cohort common T0.
- Manual Preview and Already-On Minimal BLEDIM waveform/terminal behavior are unchanged.

## Speed changes

- **Completed-turn road takeover:** rolling trace history may no longer keep the previous road merely because older samples dominate. When the old current road is >=18 m away or >=45 degrees misaligned, a different named road can take ownership when it is <=12 m away, <=20 degrees aligned, has sufficient trace support, and the vehicle is moving.
- Hard road takeover disables inherited warning eligibility and disarms old-road same-road continuity until the new road receives a fresh limit.
- **OSM road-level consensus:** an untagged current OSM segment may use a display-only inferred limit when at least two nearby explicit ways with the exact same normalized road identity agree unanimously. Conflicting speeds suppress this inference.
- **Philadelphia provider migration:** the app now queries Philadelphia's Street Centerline FeatureServer (`TRANSPORTATION_street_segment/FeatureServer/0`) and prefers `POSTED_SPEED_LIMIT`, then `SPEED_LIMIT`. Only built street geometry is requested.
- **Philadelphia turn fast-path:** a City centerline within 12 m and 20 degrees of the current course can seed the normal two-sample limit confirmation before the eight-point rolling trace has fully rotated onto the new road.
- v90.25 same-road successor continuity and same-limit pending-confirmation stale-clear suppression remain unchanged.

## Diagnostic markers

Ambient:
- `Headlight sync barrier extending for admitted preparation`
- `ENGINE-START FULL-COHORT opened`
- `ENGINE-START FULL-COHORT common T0`
- `Engine-start full-cohort promotion completed after post-crank reacquisition window without Breath`

Speed:
- `completed-turn road takeover`
- `PHILLY GIS MATCH current-geometry fast acquisition`
- `same-road corridor consensus`
- `same-road corridor consensus withheld ... conflicting=`
- existing `same-road successor fast handoff` and `pending same-limit road confirmation`
