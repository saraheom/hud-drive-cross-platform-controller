# v90.20 — BLEDIM known-good rollback

Door and Dashboard now use the exact v90.17.2 BLEDIM runtime behavior:

- power mapping: ON payload `01`, OFF payload `00`
- Breath preparation: Power ON -> RGB -> baseline brightness
- successful terminal commit: Power ON -> RGB -> final brightness
- manual ON/OFF, steady restore, Preview, and one-shot recovery all inherit that same mapping

The later no-flash preload and power-semantic experiments are intentionally removed. Sync cohort scheduling remains outside this compatibility block, so Sync ON can coordinate when preparations start without changing the field-proven BLEDIM packet sequence.

Philadelphia GIS/provider recovery and other v90.19 speed-limit changes are retained.
