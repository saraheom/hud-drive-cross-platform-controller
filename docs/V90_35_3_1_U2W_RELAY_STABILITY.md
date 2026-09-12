# v90.35.3.1 — U2W live relay stability

Field evidence from v90.35.3 showed a valid mode-6 STA/KivicCast connection followed by the app's generic HUD firmware-hello rehydration. That rehydration resent Freeride/Navigation dashboard state and could collapse the cast session after roughly one second.

Changes:
- Cancel pending HUD rehydration before starting the live U2W relay.
- Suppress firmware-hello-triggered rehydration while the live relay is active.
- Block the legacy mode-5 Map Mode control while the live relay is active.
- Keep all MainVideo / route / lane / media and 5 fps frame relay behavior unchanged.

Pair with U2W v8.14.1, which keeps KivicCast UDP discovery alive after the first reply so a transient HUD reconnect can rediscover the stream.
