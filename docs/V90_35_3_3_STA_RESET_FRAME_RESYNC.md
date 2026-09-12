# v90.35.3.3 — STA clean reset + BLE frame resynchronization

Field logs from v90.35.3.2 showed two independent failure modes:

1. HUD mode-6 STA state can remain stale/EMPTY across repeated test cycles. A fresh relay now deliberately returns to mode 4, sends the stock empty STA-network command once, waits 1.8 s, then enters mode 6 and sends the real U2W credentials.
2. BLE notifications can interleave protocol frames. Because literal STX is escaped on the HUD wire protocol, an unescaped nested STX is a definitive new-frame boundary. `HudProtocol.extractFrames` now abandons the interrupted older frame and resynchronizes to the newer event, allowing Wi-Fi status=1 packets to survive firmware-hello interleaving.

U2W v8.14.2 is unchanged and remains the required adapter image.
