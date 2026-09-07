# v90.34.9 — persistent stock Music renderer experiment + Navigation UI cleanup

## Scope

This release keeps the physically validated v90.34.8.3 boot-animation maintenance path and U2W v8.8 live navigation/lane behavior, while adding a BLE-only persistent Music experiment and removing obsolete parked/manual Navigation diagnostic cards from the iOS 26 UI.

No new HUD filesystem write is added. The only writable HUD feature remains the existing user-confirmed `/data/local/bootanimation/bootanimation.zip` override.

## Static HudLauncher findings

Inspection of the recovered stock `HudLauncher.apk` shows that `MusicNotificationPacket` has one concrete packet handler, `MainActivity$47.onPacketReceived(...)`. That handler:

1. reads the native Music packet title/message;
2. calls `HwDriveCoreView.setMusicNotificationInfo(title, message)`;
3. that method updates both `HwNotificationFrameViewMusic` and `HwNotificationFrameViewMusicMiniState`;
4. calls `HwDriveCoreView.setStateMusic(true)` to animate the stock Music renderer.

The parsed Music metadata is not published through a normal Android broadcast or a `LocalBroadcastManager` event in that Music handler. Therefore a separate companion APK cannot simply subscribe to the current stock Music packet data without an additional IPC/data path.

The launcher also contains a shared `NotificationTimeInSec` timer. `HwDriveCoreView$1.run()` clears call, message, and Music notification states after the timeout. The timeout is already controlled by the native `NotiTimeoutCommandPacket` (`command=2, p1=9, p2=1`, `int32 timeout`) used by this iOS app.

## Persistent Music experiment

Rather than patching/replacing the signed system launcher, v90.34.9 reuses the original Music renderer and periodically reasserts the existing `MusicNotificationPacket` every five seconds. This refreshes the stock notification timestamp before the normal timeout can hide the Music view.

The Media screen provides three explicit controls:

- **Start Full** — keeps the stock full Music notification renderer alive.
- **Start Mini** — enables the stock `HudHUDWidgetsMiniState` and keeps the mini Music renderer alive. This is the candidate for a side-widget-style presentation, but the firmware's mini-state command is global to the HUD layout and therefore must be physically evaluated with Navigation running.
- **Stop + Restore Normal HUD** — cancels the reassert task, leaves mini state when necessary, and restores the user's normal Music notification filter.

The experiment is opt-in per app/HUD session. It does not auto-enable after launch, does not use ADB, does not install an APK, and does not modify HUD files.

## Navigation UI cleanup

The iOS 26 Navigation screen no longer shows these obsolete diagnostic cards:

- `Ambient-light test build`
- `Manual navigation diagnostics`
- `Firmware-native lane guidance`
- `Recorded CarPlay lane replay`

Their underlying protocol/model helpers remain available in source where still useful for regression coverage; removing the cards does not change the live U2W v8.8 lane-guidance coordinator.

The Navigation screen now focuses on:

- live Route Guidance status;
- Current Street / Lane Guidance presentation settings;
- HUD Firmware Maintenance / boot-animation management.

## Suggested physical test

1. Connect HUD + U2W normally and start music through CarPlay.
2. Confirm the Media screen shows the current title/artist.
3. Tap **Start Full** and observe for at least 20 seconds. Confirm the stock Music renderer stays visible instead of timing out.
4. Tap **Stop + Restore Normal HUD** and allow the normal notification timeout to clear Music.
5. Tap **Start Mini** and observe the HUD with Navigation active. Record whether the mini Music renderer behaves like a useful side-widget presentation and whether the global mini state undesirably changes Navigation/other widgets.
6. Change tracks while persistent mode is active and confirm title/artist update.
7. Stop the experiment before entering Firmware Maintenance; the app also stops it automatically when firmware maintenance starts or HUD BLE disconnects.

