# Media and navigation sources — v90.34

The **CarPlay adapter** is the structured source for both Route Guidance and Now Playing in the current architecture.

## Navigation

Automatic physical-HUD navigation comes from the U2W Route Guidance exporter (`0x5201/0x5202/0x5204`) at `u2wrgd-live.cgi`.

- Priority: Google Maps > Apple Maps > Waze.
- Liveness: successful U2W endpoint responses + explicit active route state.
- Sequence progression is **not** a heartbeat; unchanged active Apple Maps state is valid at stoplights.
- OCR/ScreenCaptureKit does not automatically own physical-HUD Navigation.

## Media / Now Playing

The current media source is the U2W v8.6 passive CarPlay Now Playing exporter (`0x5001`) at `u2wmedia-live.cgi`, with JPEG artwork from `u2wmedia-artwork.cgi`.

The active app runtime does not depend on Spotify authorization or a Spotify SDK token. Compatible CarPlay media apps can supply the active Now Playing state.

## Notifications

ANCS remains the separate iPhone-notification path for ordinary notifications/calls supported by the HUD firmware. It is not used as the structured navigation or Now Playing source.

## Physical HUD rendering

Structured CarPlay data can be richer than the physical HUD firmware. The app can always use it in the iPhone UI, but persistent left/right physical-HUD widgets are limited to widget/rendering commands implemented by the HUD firmware. Track changes continue to use the known transient native Music notification packet.

## Protocol reference / legacy fallback

The adapter's media negotiation uses the `0x5000/0x5001` Now Playing family. Route Guidance uses the `0x5200`–`0x5204` family. ScreenCaptureKit remains in the repository only as a legacy diagnostic/fallback reference; it is not the automatic physical-HUD navigation source in v90.34.
