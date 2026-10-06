# U2W v8.32 — Safe Bounded Checkpoint MainVideo

This release is intentionally a narrow recovery extension of the v8.31 safety model.

## Safety boundary
- Exact proven v8.11 MainVideo exporter remains untouched.
- AppleCarPlay and ARMiPhoneIAP2 are never killed, signaled, restarted, injected, or source-reselected.
- Route Guidance, Now Playing, and the v8.15.1 HUD JPEG relay are untouched.
- No boot hook or relay autostart. The relay exists only after an explicit app Map Mode/live-preview request.
- Installer accepts the exact v8.31 relay SHA1 only: `b3964792342f9bc5ad22eaeb70eaf84ec04562f6`.

## Recovery model
- TCP/15332 wire magic: `U2WH2649` + repeated `[u32BE length][validated NAL]`.
- Strict 800×480 SPS/PPS/VCL validation.
- Type-5 NALs are trusted as IDR only when the slice is intra-coded and `frame_num == 0`.
- Reference `frame_num` discontinuity quarantines dependent pictures until the next genuine IDR.
- One current-generation checkpoint only; hard cap **1,572,864 bytes (1.5 MiB)**.
- One forward scan of the **current** v8.11 mirror at on-demand process startup. No archived-generation/history scan and no generation reseed loop.
- A new/recovering client receives the validated checkpoint when available; otherwise it remains connected on heartbeats until a new genuine IDR creates a safe epoch.
- If the checkpoint exceeds the hard cap, it expires rather than growing memory.

## Memory
Static BSS: **2,426,196 bytes**. This is deliberately far below v8.30's ~13.7 MiB stateful relay and v8.25's 48 MiB recovery-cap design.

## Rollback
`U2W_Update_v8.32_SAFE_ROLLBACK_v8.31.img` restores the exact v8.31 raw relay and does not start it.
