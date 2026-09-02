# Media and navigation sources

Physical iPhone testing established that the accessory notification path works
for normal Notification Center events such as Messages and KakaoTalk. Spotify
current-track metadata and live turn-by-turn guidance do not reliably arrive
through ANCS, so media/navigation remain separate source classes.

## Preferred path: CarPlay adapter metadata

The current development priority is the CarPlay adapter rather than further
iOS 27 ScreenCaptureKit work.

The tested Carlinkit U2W stock firmware already exchanges Now Playing message
IDs `0x5000/0x5001`. Experimental Route Guidance support is being tested by
advertising the Route Guidance component `0x001E` and exposing the `0x5200`–
`0x5204` family:

- `0x5200` — route-guidance start
- `0x5201` — route-guidance update
- `0x5202` — maneuver
- `0x5203` — route-guidance stop
- `0x5204` — lane guidance

The adapter test remains intentionally separate from the production HUD app
until the field capture verifies that iPhone/CarPlay actually sends the desired
Now Playing and live route-guidance payloads. Once verified, the preferred HUD
architecture is to ingest/export those adapter messages directly and feed the
existing media/navigation UI from structured metadata rather than screen pixels.

## Other sources

- ANCS notifications: Messages, calls, mail, social/messaging notifications.
- Media / Now Playing: prefer CarPlay adapter `0x5000/0x5001` metadata once the
  exporter is field-verified.
- Navigation: prefer CarPlay adapter Route Guidance `0x5200`–`0x5204` once the
  experimental Identify/registration patch is field-verified.
- ScreenCaptureKit: retain only as an experimental fallback/reference path; do
  not make additional iOS 27 beta capture work the primary integration plan
  while the adapter metadata path is being validated.

This keeps the working notification pipeline separate from future structured
CarPlay media/navigation integration while avoiding unnecessary dependence on
screen capture.
