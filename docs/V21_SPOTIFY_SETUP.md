# v21 Spotify-only setup

This version intentionally contains no in-app navigation engine.

Navigation remains external-only:
- Apple Maps
- Google Maps
- Waze
- future external map sources

The existing manual HUD maneuver pipeline remains available for testing, but
v21 does not calculate routes inside HUD Controller.

## Spotify bridge

1. Create a Spotify Developer app.
2. Use bundle ID:
   `com.jjunnyy.hudcontroller`
3. Add redirect URI:
   `jjunnyy-hud-login://spotify-callback`
4. Copy the Spotify Client ID.
5. In GitHub:
   Settings → Secrets and variables → Actions → New repository secret
6. Add:
   `SPOTIFY_CLIENT_ID`
7. Secret value:
   your Spotify Client ID
8. Run iOS CI and then the TestFlight workflow.

## iPhone test

1. Connect the HUD.
2. Enable All notification apps while testing.
3. Open Media.
4. Tap `Send Media Test Notification`.
5. Confirm the HUD displays the local test notification.
6. Start Spotify playback.
7. Tap `Connect / Authorize Spotify`.
8. Approve Spotify authorization.
9. Change tracks and verify the Media screen updates.
10. Check whether artist/title notifications appear on the HUD.

If the manual media test reaches the HUD but Spotify metadata does not, the
remaining problem is Spotify authorization/player-state handling rather than
the notification bridge.
