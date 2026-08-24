# v90.5 — BLEDIM FFF1 protocol recovery + corrected shutdown sequence

## Why v90 BLEDIM control was retired

Physical testing of both BLEDIM2-compatible controllers proved that the v90
9-byte `7E FF ... EF` command family does not control these devices. Both
controllers connect correctly and expose the expected application GATT path:

- service `FFF0`
- characteristic `FFF1`
- `writeWithoutResponse` + `notify`

The old packets were from a different LED-controller family commonly exposed as
`FFE0/FFE1`. v90.5 removes those guessed packets completely. Normal BLEDIM
Power/Color/Brightness controls and automatic BLEDIM fades are disabled until an
exact packet from the official BLEDIM/BLEDIM2 application is captured and
validated.

## Protocol-lab support

For each paired BLEDIM device v90.5 can:

- connect/reconnect to `FFF0/FFF1`;
- enable FFF1 notifications and log every response;
- read standard Device Information and Battery characteristics;
- record advertised service/manufacturer/service-data metadata;
- replay a user-supplied captured hexadecimal packet directly to FFF1.

The raw replay path is deliberately hard-wired to FFF1 and never writes the
Texas Instruments OAD service `F000FFC0...` / `FFC1` / `FFC2`.

Recommended official-app capture on one controller:

1. OFF
2. ON
3. solid red
4. solid green
5. solid blue
6. brightness 100%
7. brightness 50%
8. brightness 10%

An Android Bluetooth HCI snoop / btsnoop capture containing those operations is
the preferred source. Once the exact frames are known, they can be replayed in
the v90.5 FFF1 Protocol Lab before promoting them into normal automation.

## Corrected physical shutdown sequence

The Door BLEDIM controller is engine-switched. Therefore engine OFF removes Door
power immediately and there is no opportunity to fade it after shutdown. v90.5
records Door runtime brightness as 0 locally but does not transmit a Door fade.
Door Day/Night/preferred targets are preserved.

The Dashboard BLEDIM and Lotus Center Console are headlight-fed:

### Daytime arrival

- while driving: Door on; Dashboard + Console off;
- engine OFF: Door loses power immediately;
- after exit/lock: courtesy headlights can power Dashboard + Console for roughly
  1–2 minutes.

### Night arrival

- while driving: all three are on;
- engine OFF: Door loses power immediately;
- Dashboard + Console remain powered;
- after exit/lock: Dashboard + Console remain powered for roughly 1–2 minutes.

On confirmed engine OFF, v90.5 arms a shutdown latch until the next engine ON.
Verified headlight-fed controllers are faded to 0 if already present. Any verified
headlight-fed controller that appears later during the courtesy interval is
immediately restored to its preferred color/power state at runtime brightness 0.

At present the Lotus controller can be suppressed this way. The Dashboard BLEDIM
controller cannot yet be commanded until its FFF1 payload is decoded; the app
logs this limitation explicitly rather than pretending the fade succeeded.
