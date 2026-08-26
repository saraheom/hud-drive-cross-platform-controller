# v90.9 BLEDIM animation reliability

## Field symptom

v90.8.2 Breath could begin smoothly, become choppy, disconnect a controller, or finish
at 0–5% until Preview/Power was used again. Lotus Lantern generally looked smoother
than the two BLEDIM2 controllers.

## Root causes confirmed by logs/capture

1. The official BLEDIM2 iOS app's captured brightness-slider traffic is approximately
   one write every 100 ms (~10 Hz). v90.8.2 animated BLEDIM at 20 Hz.
2. Door and Dashboard shared one sequence counter, interleaving the sequence stream
   observed by each physical controller.
3. The paired-device watchdog repeatedly rediscovered GATT services/characteristics
   while animation was active, producing unnecessary callbacks and Device Information
   reads.
4. Every intermediate animation packet and notification was synchronously appended to
   the diagnostic log on the MainActor.
5. A repeated Breath request while already active recaptured the current animation
   frame as a new start/return brightness. In the field log this happened near the
   bottom of the fade and led to final values near 1–5%.
6. Fixed-frame-count timing meant MainActor/BLE delays stretched the requested total
   animation duration instead of simply skipping stale visual frames.

## v90.9 behavior

- Shared animation phase clock: 20 Hz.
- Lotus output cadence: up to 20 Hz.
- BLEDIM output cadence: up to 10 Hz, matching official-app continuous-slider traffic.
- Animation progress is derived from wall-clock elapsed time.
- Writes obey CoreBluetooth write-without-response backpressure.
- Intermediate frames may be skipped, never queued and replayed late.
- Final target gets bounded retries.
- BLEDIM sequence number is maintained independently per peripheral.
- Repeated Preview/ON while a light is already breathing is ignored for baseline
  capture, so the original start/return brightness is preserved.
- A reconnect restores the steady intended brightness, not a stale transient frame.

## Editable presets

Each light and each group has five independent persistent color slots. Tap a block to
apply it. Select a new picker color and tap the pencil below a slot to replace it.
