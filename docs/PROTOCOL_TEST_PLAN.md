# HUDWAY BLE Protocol Test Plan

Test while parked and with all phone connections to the HUD disconnected.

## Connection baseline

1. Scan and select the HUD.
2. Connect to Nordic UART service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`.
3. Subscribe to RX characteristic `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`.
4. Write to TX characteristic `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` without response.
5. Save all TX/RX logs.

## Command order

1. Connect only.
2. Send keep alive.
3. Run Initialize HUD.
4. Toggle Auto Brightness ON/OFF.
5. Toggle Navigation ON/OFF.
6. Send Right, 46 m, `Turn right / Main St`.
7. Update distance to 15 m without changing maneuver.
8. Change maneuver to Left.
9. Send Destination.
10. Disable navigation.

For each test, record visible HUD behavior, exact TX bytes, exact RX bytes, and timing.
