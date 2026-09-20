# v90.35.3.24 / U2W v8.24 capture validation

This validation was performed before packaging using the already-collected 2026-09-19 MainVideo captures. It is specifically intended to cover the two opposite startup orderings observed in the car without requiring another exploratory drive.

## Field evidence being addressed

The latest failed parked test showed the v8.23 relay had already accepted one valid IDR before the iPhone TCP client connected. The client then waited for a *future* valid IDR while thousands of P-slices arrived. The prior successful parked test had the opposite ordering: the iPhone was connected first and the valid SPS/PPS/IDR arrived afterward.

The captured `U2W_MAINVIDEO_V811_DUMP (17).tar.gz` stream contains a valid 800×480 H.264 bootstrap at the beginning (`SPS → PPS → IDR`) followed by a long P-frame reference chain. A later type-5-looking candidate is not a usable decoder anchor, matching the v8.23 relay's decision not to bootstrap from it.

## Bounded recent-IDR simulation

The v8.24 policy was replayed against that captured stream with a 4 MiB recent-anchor cap. Simulated client connection points:

| Client position relative to valid IDR | Expected v8.24 path | ffprobe result |
|---|---|---|
| before IDR (`0`) | fresh live bootstrap | 800×480, 514 frames, no ffprobe errors |
| immediately after IDR (`7490`) | recent-anchor bootstrap | 800×480, 514 frames, no ffprobe errors |
| `200000` bytes later | recent-anchor bootstrap | 800×480, 514 frames, no ffprobe errors |
| `1000000` bytes later | recent-anchor bootstrap | 800×480, 514 frames, no ffprobe errors |
| `3000000` bytes later | recent-anchor bootstrap | 800×480, 514 frames, no ffprobe errors |
| `4500000` bytes later | anchor intentionally over cap | no replay; wait for next valid IDR |

This directly validates both startup orderings seen in the field while keeping replay bounded well below the unsafe 17–20 MiB v8.22 burst.

## Continuity/recovery changes

The captured streams also show that valid IDRs can be sparse for long periods. Therefore v90.35.3.24 does not intentionally recycle the decoder during normal operation. It:

1. starts MainVideo predecode early in the app session, before HUD BLE is ready;
2. preserves MainVideo across HUD BLE transport loss;
3. prefers the software VideoToolbox H.264 decoder for the small 800×480 navigation surface, avoiding the hardware-session invalidation pattern correlated with iOS lifecycle transitions;
4. preserves the decoder across foreground/background lifecycle notifications and lets actual output-stall/fatal-error evidence drive recovery;
5. if hard decoder recovery is truly required, reconnects to v8.24 so a still-valid bounded recent-IDR anchor can be replayed immediately.

A fully recreated H.264 decoder still fundamentally needs a valid reference anchor. If the last valid IDR is older than the bounded 4 MiB recent window and a decoder is genuinely destroyed, recovery must wait for another valid IDR. The software-decoder/lifecycle changes are specifically intended to prevent the field-observed invalid-session failure that previously forced that condition.
