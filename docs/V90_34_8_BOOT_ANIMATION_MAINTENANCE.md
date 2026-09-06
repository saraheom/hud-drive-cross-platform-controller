# v90.34.8 Boot Animation Maintenance

## Scope

This phase implements one reversible HUD filesystem write: `/data/local/bootanimation/bootanimation.zip`. It does not remount or modify `/system`, does not invoke KivicSystemUpdater, and does not perform an OTA/recovery flash.

## Why this override is appropriate

The recovered HUD `/system/bin/bootanimation` contains the lookup path `/data/local/bootanimation/bootanimation.zip` in addition to `/system/media/bootanimation.zip`. The stock system archive is 480×240 at 24 fps and uses stored ZIP entries with `part0` once and `part1` looping. The app follows that native format.

## Maintenance transport

Physical testing established the stock Wi-Fi lifecycle:

- `HudHotspotBaseband(is5G:true, forceEnable:false)`
- `KivicMode(5)`
- hold mode 5 while HudLauncher starts hostapd/tethering/dnsmasq
- HUD address `192.168.43.1/24`
- ADB TCP `192.168.43.1:5555`
- `ro.adb.secure=0`

Before enabling any write, the app verifies `ro.kivic.model=HUDWAY Drive`, `ro.kivic.firmware.version=1.1.27`, and `ro.adb.secure=0`. The exact identity is re-checked immediately before installation; another model/firmware is rejected in this first field build.

The app intentionally does not request a new HotspotConfiguration entitlement in this release. Start maintenance, wait for the AP, join the HUD network manually in iPhone Settings, return to the app, then tap Reconnect ADB.

## Input preparation

Accepted inputs:

- MP4 / MOV / M4V video, at most 12 seconds for this field-validation release; or
- Android `bootanimation.zip` already matching the HUD.

Video conversion produces actual 480×240 PNG pixels at 24 fps with black aspect-fit letterboxing. The ZIP writer uses method 0 (STORE/no compression), matching the stock archive. `desc.txt` is:

```text
480 240 24
p 1 0 part0
p 0 0 part1
```

The final converted frame is copied to `part1/frame_000.png`, so the HUD holds the final logo frame if Android takes longer to finish booting.

Imported ZIP validation requires the same descriptor, stored entries, at least one `part0` PNG, a stored `part1/frame_000.png`, and exact 480×240 PNG dimensions. Maximum archive size is 100 MB.

## Install transaction

The app writes only after an explicit Install alert. It first checks that `/data/local/bootanimation` exists and is writable. It uploads to:

```text
/data/local/bootanimation/bootanimation.zip.pending
```

The app then reads the whole file back using ADB SYNC RECV and computes SHA-256 incrementally. Size and SHA-256 must equal the local prepared archive before commit. The commit is an atomic rename to:

```text
/data/local/bootanimation/bootanimation.zip
```

followed by mode `0644`. A second full read-back hash verifies the committed override. On pre-commit failure the pending file is deleted.

## Rollback

Restore Stock removes only:

```text
/data/local/bootanimation/bootanimation.zip
/data/local/bootanimation/bootanimation.zip.pending
```

No stock system file is touched. The next reboot should therefore fall back to `/system/media/bootanimation.zip`.

## First physical test

1. Connect the custom app to the HUD over BLE.
2. Open Navigation → HUD Firmware Maintenance.
3. Tap Start Firmware Maintenance and wait about 5 seconds.
4. In iPhone Settings → Wi-Fi, join `HUDWAY Drive(7612)` with password `87654321`.
5. Return to the app and tap Reconnect ADB. Verify the HUD identity shows HUDWAY Drive / FW 1.1.27.
6. Select a short animation video or valid stored `bootanimation.zip`.
7. Tap Install Custom Boot Animation and approve the write confirmation. Wait for upload + read-back verification to complete.
8. Tap Reboot HUD to Test Animation and approve the reboot. Keep HUD/vehicle power stable through startup.
9. If the result is undesirable, re-enter maintenance, Reconnect ADB, choose Restore Stock, then reboot.

Do not power-cycle during the upload/commit operation. The system partition remains untouched throughout this phase.
