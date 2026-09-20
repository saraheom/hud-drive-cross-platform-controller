# v90.35.3.24.1 CI alignment

This is a test-only CI alignment on top of v90.35.3.24. Production app behavior and U2W v8.24 firmware are unchanged.

The iOS 26 CI run compiled the app successfully, then failed four source-string assertions in three older ambient regression tests. Those assertions still described the superseded v90.35.3.22/v90.35.3.23 Dashboard+Center BOTH-OFF consensus path. v90.35.3.24 intentionally restores Center/BLEDOM as the authoritative day/night witness, with a short Center-only absence guard and Dashboard used only as a diagnostic cross-check.

Updated tests:
- `V9010AmbientPowerEpochReliabilityTests` now requires the Center-only guard and diagnostic-only Dashboard contract and explicitly rejects the removed fast BOTH-OFF ownership path.
- `V903522LiveIDRLaneAmbientTests` now checks the short Center-only NIGHT guard used after a Center BLE transport disconnect.
- `V903523DecoderLaneAmbientTests` now checks guarded Center absence → DAY, recovery during the guard, and diagnostic Dashboard consensus.

No production source, MainVideo logic, decoder behavior, ambient-light runtime behavior, or U2W firmware bytes were changed.
