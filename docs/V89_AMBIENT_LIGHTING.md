# v89 Ambient Lighting

## Architecture

`AmbientLightMonitor` remains the single CoreBluetooth owner used by the old
HUD Auto Brightness presence trigger. v89 extends it with paired devices,
protocol adapters, GATT discovery, direct writes, and logical groups. This
avoids two iOS central managers independently trying to own the same ELK-BLEDOM
peripheral.

The UI lives under Vehicle → Ambient Lighting Control rather than adding a sixth
root tab.

## Lotus Lantern 6.5.08 findings

Recovered from `com.easylink.colorful.service.BluetoothLEService` in the supplied
decompiled project:

- `SEND_DATA_SERVICE_UUID = 0000fff0-0000-1000-8000-00805f9b34fb`
- `SEND_DATA_CHARACTERISTIC_UUID = 0000fff3-0000-1000-8000-00805f9b34fb`
- app connection limit is four GATT devices, so three car lights are within the
  source app's design envelope;
- the Android implementation requests MTU 63 after connection.

Implemented packet family:

```
power on    7E 04 04 01 00 01 FF 00 EF
power off   7E 04 04 00 00 00 FF 00 EF
RGB          7E 07 05 03 RR GG BB 10 EF
brightness   7E 04 01 XX FF FF FF 00 EF
```

The decompiled app has a special encrypted branch only when the advertised name
literally contains `ELK-*`. v89 blocks direct writes for that marker rather than
pretending the ordinary packet family is valid. A normal `ELK-BLEDOM` name does
not select that branch in the supplied Android source.

## BLEDIM2

BLEDIM2 1.960 is Jiagu-packed. Static extraction confirms the protection loader,
but does not expose the real GATT constants or write packet construction. v89
therefore logs every discovered service and characteristic (including write
properties) for paired BLEDIM2 lights and keeps control writes disabled until a
real command capture is available.

Recommended capture sequence for one BLEDIM2 controller:

1. Connect with the official BLEDIM2 app.
2. Power OFF.
3. Power ON.
4. Set solid red (255,0,0).
5. Set solid green (0,255,0).
6. Set solid blue (0,0,255).
7. Set brightness 100%.
8. Set brightness 50%.
9. Set brightness 10%.
10. Save/export the Android Bluetooth HCI snoop log.

Those writes are sufficient to identify the service, characteristic, packet
framing, byte positions and brightness scale. One controller should be enough
unless the second unit reports a different GATT fingerprint in the HUD log.
