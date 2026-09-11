# v90.35 — custom Map Mode cast + native OBD-speed overlay probe

v90.35 turns the v90.34.17 visual preview into a bounded physical-HUD experiment while retaining the normal Freeride/Navigation pipeline as the fallback. No HUD APK, system partition, boot image, or firmware file is modified.

## Approved HUD-safe layout

The custom 480×240 composition follows the original HUDWAY readability philosophy rather than filling every edge of the reflector:

- **Left:** current speed + U.S.-style rectangular SPEED LIMIT sign.
- **Center:** simplified map / route composition with a large route corridor and sparse labels.
- **Right:** turning street → maneuver graphic → distance → lane guidance → ETA → time left.
- Extreme top/bottom corners remain intentionally sparse.

Reference concept: `docs/images/V90_35_MAP_MODE_CONCEPT.png`.

Every component can be shown/hidden independently. Left, center and right widgets each have an independent 60–145% size control. These are custom-renderer settings and do not alter the stock HUD dashboard packet.

## Map appearance

Three presentation choices are persisted:

- **Follow source** — the intended production behavior once real U2W MainVideo frames are exposed to iOS. It will preserve the actual Google Maps / Apple Maps / Waze pixels, including the source app's own day/night mode.
- **Dark HUD** — custom high-contrast schematic map.
- **Light HUD** — custom light schematic map.

The current v90.35 physical test does **not** yet receive live U2W video frames. The v8.10 capture proved that the adapter sees the main CarPlay H.264 stream but did not expose an app-friendly frame endpoint. Therefore Follow source uses the dark schematic fallback in this release. The renderer is isolated so the center map can later be replaced by a real cropped frame without redesigning the left/right widgets.

## Route data used by the schematic

While U2W Route Guidance is reachable, the app now retains:

- current road;
- destination;
- current/next maneuver data;
- distance;
- ETA;
- time remaining;
- unique route-road names from the exported maneuver table;
- resolved live lane values.

When Map Mode is enabled the app freezes the last semantic U2W route before the iPhone moves from the Carlinkit network to the HUDWAY AP. GPS speed and the selected speed limit remain live; route text/map labels remain frozen until the normal Carlinkit connection is restored.

## Physical Map Mode cast

**Enable Map Mode on HUD** performs only stock network/display actions:

1. Cache the current U2W semantic route.
2. Pause U2W Route Guidance / Now Playing polling so Wi-Fi handoff cannot trigger stale navigation-release traffic.
3. Start the local KivicCast responder:
   - UDP discovery port `15320`;
   - HTTP Motion-JPEG port `15330`;
   - `KVMJPEG/1.0` discovery response with an HTTP stream descriptor;
   - 480×240 JPEG frames at approximately 5 fps.
4. Send the already-validated stock HUD AP bootstrap:
   - 5 GHz, `forceEnable=false`;
   - `IOS_KIVICCAST_MODE(5)`.
5. User joins the **HUDWAY Drive** Wi-Fi on the iPhone.
6. The HUD's stock KivicCast viewer should discover the iPhone stream and request MJPEG.

This is a first physical compatibility test of the recovered viewer protocol. The normal app can still be restored with **Disable Map Mode** even if the viewer does not accept the first MJPEG attempt.

## Native OBD speed overlay experiment

The stock HUD already receives ECU vehicle speed internally, but the stock HUD→iPhone event protocol does not return that live PID value. v90.35 tests whether the HUD can render that value itself over the cast image:

- the setting **Native OBD speed overlay experiment** is ON by default;
- when HUD-side OBD is connected, the physical custom MJPEG frame intentionally leaves the speed-number area blank;
- after an MJPEG client begins streaming, the app sends:
  - `fullScreen(false)` to re-open the stock HUD layer;
  - `OBDIICustomItemInternalPacket(position=0, itemIndex=10)` three times with bounded spacing;
- item index 10 is the recovered `OBD_DRIVING_VELOCITY` enum value.

If a speed value appears in the reserved left-side area, it is therefore evidence of the native OBD renderer rather than the app's GPS speed. The in-app preview continues showing speed so layout customization remains practical.

Disabling Map Mode sends OBD item `NONE`, returns to `IOS_HUD_MODE(4)`, restores full screen, reapplies normal dashboard profiles, time/weather, lane policy and the speed-marker state, then resumes U2W polling.

## Time/weather correction

v90.34.16's cold-start workaround sent a transient time/weather **ON** packet even when the saved setting was OFF. The September 11 field drive showed that this could leave the panel visible. v90.35 removes that ON edge entirely. A saved OFF state now receives OFF-only reasserts, including the delayed cold-session reassert.

## First test sequence

1. Start the car normally and allow HUD + OBD + U2W Route Guidance to connect.
2. Open Navigation → Custom Map Mode.
3. Adjust left/center/right size and component visibility if desired.
4. Leave **Native OBD speed overlay experiment** ON for the first test.
5. Tap **Enable Map Mode on HUD**.
6. After about five seconds, join the HUDWAY Drive Wi-Fi on the iPhone.
7. Return to the app and observe Map Mode status / logs.
8. Check the physical HUD for the 480×240 custom layout.
9. If a speed number appears in the reserved left-side speed position, compare it with vehicle speed; it should be produced by the HUD's OBD path.
10. Tap **Disable Map Mode**, then reconnect the iPhone to Carlinkit Wi-Fi if iOS does not do so automatically. Normal U2W Navigation/Freeride should resume.

## Safety / scope

- No APK installation or replacement.
- No `/system` remount or write.
- No updater command.
- No boot-animation write.
- No U2W firmware change.
- Map Mode always starts OFF after app launch; ON is not persisted.
