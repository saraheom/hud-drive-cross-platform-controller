# v90.35.3.11 — combined road-test instrumentation

## Purpose

This app-only revision is intended to collapse several pending questions into one car test while leaving the proven U2W v8.15.1 relay untouched.

## OBD speed investigation

The iPhone does **not** create a second connection to the OBD adapter. The HUD remains the OBD owner. The BLE manager passively annotates completed HUD RX frames against the simultaneous GPS speed. The trace records packet header `(command/p1/p2)`, payload length/hex, GPS mph/km/h, and scalar candidates that numerically track speed as u8, u16 BE/LE, u32 BE/LE, or Float32 BE/LE. Known OBD status `(3/7/1)` is decoded separately.

The Vehicle tab exposes `OBD speed protocol trace`; it defaults ON on a fresh install. Relevant log tags are `OBD TRACE`, `OBD TRACE RX`, and `OBD STATUS`.

A manual Map Mode visual probe is also available under image customization. For 12 seconds the custom GPS speed is blanked. Phase 1 requests stock `OBD_DRIVING_VELOCITY` without changing fullscreen. Phase 2 repeats the request with `fullScreen(false)` for six seconds. If the HUD overlays a live speed number, that proves the HUD can present its internally decoded OBD speed over mode 6 even if the numeric value is never returned to iOS. The probe clears the custom OBD slot and restores fullscreen automatically; it deliberately does not re-send mode 6.

## Speed-limit sign customization

Two persisted controls are added under Map Mode image customization:

- Sign height: 80–200% of the previous 34 px height.
- Number font size: 70–160% of the previous 24 pt numeral.

Sign width stays 42 px. Styling remains white rectangle, black border, black number, no `SPEED LIMIT` text.

## Mode 6 → 4 STA persistence experiment

Under Map Mode `Status & diagnostics`, the association test:

1. Requires an already-active relay and valid HUD `192.168.50.x` STA address.
2. Leaves U2W daemons and iPhone frame ingress running.
3. Sends only `IOS_HUD_MODE(4)` and restores the normal dashboard renderer.
4. Requests stock `WifiSTAStatusEventPacket` at approximately 1.5, 3.0, and 6.0 seconds.
5. Reports whether the HUD still claims a live STA link and whether the IP remained unchanged.

`Return Map Mode — mode 6 only` then sends only mode 6, intentionally no credentials, and watches U2W's session-scoped MJPEG state for up to six seconds. This isolates whether association survives mode 4 and can make future Map Mode activation nearly instantaneous.

## Unchanged

U2W v8.15.1, MainVideo rotation/freshness handling, Route Guidance 45-second transient holdover, no-known-image startup primer, ambient-light state machine/reconnect behavior, and normal relay start/stop sequencing are unchanged.
