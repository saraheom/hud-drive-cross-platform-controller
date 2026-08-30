# v90.7 — BLEDIM2 protocol recovered from official iOS capture

On 2026-08-24 the official BLEDIM2 iOS app was captured using Apple's Bluetooth diagnostic profile and an iPhone sysdiagnose/PacketLogger trace while controlling the Dashboard BLEDIM-A controller (`7A3B5F81…5F81`).

The trace proves that the application transport is ATT Write Command (`0x52`) to the value handle corresponding to service `FFF0`, characteristic `FFF1`.

## Frame

```
55 AA SS CC LL LL [payload...] XX
```

- `55 AA`: fixed header
- `SS`: monotonically increasing 8-bit sequence byte
- `CC`: command
- `LL LL`: big-endian payload length
- `XX`: modulo-256 sum of every preceding byte in the complete frame

`FFF1` supports `writeWithoutResponse + notify`, matching the captured ATT Write Command behavior.

## Commands

### Power — command 0x80

Payload: one byte. The frame bytes were recovered correctly from PacketLogger, but later direct in-vehicle field testing on **both** BK-BLE controllers (Door and Dashboard, 2026-08-30) proved the earlier UI-state interpretation was reversed:

- `00` = **physical ON**
- `01` = **physical OFF**

The original capture had correctly identified command `0x80`; only the semantic label assigned to its two payload values was wrong.

Captured:

```
PHYSICAL ON   55 AA 09 80 00 01 00 89
PHYSICAL OFF  55 AA 0A 80 00 01 01 8B
```

The two raw frames above remain authoritative protocol evidence. Direct vehicle testing is authoritative for their physical ON/OFF meaning.

### RGB — command 0x82

Payload:

```
00 RR GG BB 00 00 FF 00 80 00 00 00
```

Captured:

```
RED    55 AA 0B 82 00 0C 00 FF 00 00 00 00 FF 00 80 00 00 00 16
GREEN  55 AA 0C 82 00 0C 00 00 FF 00 00 00 FF 00 80 00 00 00 17
BLUE   55 AA 0E 82 00 0C 00 00 00 FF 00 00 FF 00 80 00 00 00 19
```

The selected purple point from the official UI produced RGB `2D 00 FF`, confirming the three variable bytes are RGB:

```
55 AA 0D 82 00 0C 00 2D 00 FF 00 00 FF 00 80 00 00 00 45
```

### Brightness — command 0x88

Payload:

```
02 VV 00 00 00 00
```

where `VV` is a 0...255 brightness channel. v90.7 maps the app's 0...100% control linearly to 0...255.

Captured endpoints:

```
0% endpoint    55 AA 12 88 00 06 02 00 00 00 00 00 A1
100% endpoint  55 AA 28 88 00 06 02 FF 00 00 00 00 B6
```

The official app emitted multiple intermediate frames while the brightness slider was dragged, which is why the nominal 10% and 50% user stops did not land exactly on 0x1A and 0x80 in the trace.

## v90.7 behavior

- BLEDIM normal Power, Color, and Brightness controls are re-enabled.
- BLEDIM startup animation is re-enabled.
- Door day/night brightness automation can now command the Door BLEDIM controller.
- Dashboard headlight join/startup/shutdown courtesy suppression can now command the Dashboard BLEDIM controller.
- Group fan-out now includes BLEDIM members.
- The raw FFF1 lab is retained only as an advanced diagnostic.
- The disproved v90 `7E FF ... EF` packet family remains removed.
- TI OAD `F000FFC0/FFC1/FFC2` is never used for light control.

## First physical verification

Before relying on vehicle choreography, manually verify one BLEDIM device while parked:

1. Power OFF, then ON.
2. Set Red, Green, Blue.
3. Set brightness 20%, 50%, 100%.
4. Export the HUD diagnostic log if anything differs from the requested effect.

The Dashboard capture is the authoritative source for this protocol. Subsequent v90.7 field testing confirmed the same Power/RGB/Brightness implementation also works on the Door controller (`FBD8C9A0…C9A0`).
