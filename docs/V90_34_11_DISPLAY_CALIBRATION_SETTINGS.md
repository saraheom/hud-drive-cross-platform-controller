# v90.34.11 — Original HUDWAY display calibration + Settings reorganization

## Scope

This build starts from v90.34.10.2 and adds the original HUDWAY Drive 1.4.6 **Scale** and **Perspective** controls without changing the HUD firmware, system APK, U2W exporter, CarPlay route pipeline, ambient-light logic, or boot-animation safety boundary.

The Navigation page no longer contains the HUD Firmware Maintenance card. A persistent top-right **gear** opens a new Settings page containing:

1. **HUD Display** — original Scale and Perspective sliders.
2. **HUD Firmware Maintenance** — the existing reversible boot-animation workflow, moved intact from Navigation.

## Stock Scale / Perspective protocol

The original Android 1.4.6 JADX project was re-audited rather than inferring behavior from the UI screenshot.

### Scale

`HwSubSettingPresenterAdvanced.setLayoutSize(value)` maps the 0–100 seeker to:

`layoutSize = value * 0.2 / 100`

and calls `HwDeviceCommunicationProxy.setHUDLayoutSize(layoutSize)`.

`LayoutSizeCommandPacket` is `CommandPacket(p1=14, p2=0)` and its complete payload is one Java `DataOutputStream.writeFloat(layoutSize)` value. The custom iOS implementation therefore sends command body:

`02 0E 00 <Float32 big-endian>`

with a stock range of `0.00 ... 0.20`.

### Perspective

`HwSubSettingPresenterAdvanced.setPerspective(value)` maps the 0–100 seeker to:

`keyStone = value * 0.1 / 100`

and calls `HwDeviceCommunicationProxy.setKeystoneValue(keyStone)`.

`KeyStoneCommandPacket` is `CommandPacket(p1=3, p2=0)` and its complete payload is one Java `DataOutputStream.writeFloat(keyStone)` value. The iOS implementation sends:

`02 03 00 <Float32 big-endian>`

with a stock range of `0.00 ... 0.10`.

Both settings default to stock `0`, persist locally, apply live while the HUD is connected, and are reasserted during the existing phase-2/phase-3 HUD rehydration sequence after reconnect or firmware restart. Slider traffic is debounced by 90 ms to avoid filling the serialized BLE queue during a drag.

## Per-widget scale / perspective research

Per-widget calibration was explicitly audited before adding any experimental control.

The recovered stock phone protocol exposes only:

- global `LayoutSizeCommandPacket`: one Float32, no widget/slot identifier;
- global `KeyStoneCommandPacket`: one Float32, no widget/slot identifier;
- `HudWidgetCommandPacket`: left/center/right widget **names** plus layout type, with no scale/perspective field.

Therefore there is no validated stock BLE packet that means “scale only left/center/right widget” or “apply keystone only to one widget.” v90.34.11 does **not** invent an unknown packet. Per-widget calibration remains a read-only firmware-research target; implementing it safely would require finding a hidden receiver/API in HudLauncher or another firmware component first.

## Firmware maintenance relocation

All existing boot-animation safety behavior remains unchanged. Settings still:

- enters the physically validated HUD 5-GHz mode-5 maintenance path;
- connects ADB only to `192.168.43.1:5555` after identity checks;
- writes only `/data/local/bootanimation/bootanimation.zip` through pending-file + read-back SHA-256 verification;
- never remounts or modifies `/system/media/bootanimation.zip`;
- requires explicit confirmations for install, restore, and reboot.

Only the SwiftUI location of that UI was changed.
