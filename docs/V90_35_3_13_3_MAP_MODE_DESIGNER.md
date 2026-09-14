# v90.35.3.13.3 — Map Mode 3-preset layout designer

This release layers the visual designer on top of v90.35.3.13.2.1 stabilization. U2W v8.17, MainVideo decoding, HUD viewer recovery, route guidance, media, ambient lighting, and OBD forensic behavior are unchanged.

## Lossless migration

On the first launch of v90.35.3.13.3, the exact Map Mode customization already stored in `UserDefaults` is captured before any preset is loaded. That snapshot becomes Preset 1 and is also retained as a separate pre-designer recovery snapshot. Presets 2 and 3 initially clone that same known-good layout.

## Designer

The editor uses the actual 480×240 render canvas. Select Speed, Speed limit, Map, Street, Maneuver, Distance, Lanes, ETA, or Time left, then drag anywhere on the preview. Movement snaps to 2 physical HUD pixels and is bounded. Arrow buttons allow precise 2-pixel nudges and the selected component has a size slider.

Designer movement is stored as a new delta on top of the legacy calibration. Therefore zero designer offsets reproduce the pre-existing layout exactly. Existing map crop, widget scaling, detailed right-side tuning, visibility controls, speed-limit styling, and component spacing remain available and are included independently in each preset.

## Presets

All three presets auto-save. Switching presets first saves the current slot, then restores the complete target snapshot. The active slot is also persisted across launches. `Duplicate` copies the current design into another slot and switches to it. `Restore pre-designer layout` restores the layout captured during migration into the active slot.

## Not included yet

No speed-limit warning effect is added here. That remains gated on obtaining a trustworthy OBD2 vehicle-speed source, per the current test plan.
