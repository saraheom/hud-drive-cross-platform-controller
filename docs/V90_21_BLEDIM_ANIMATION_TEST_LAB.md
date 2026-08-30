# v90.21 — BLEDIM animation strategy test lab

Purpose: compare BLEDIM Door/Dashboard command sequencing in one installed build.

Automatic default remains **v90.17.2 Baseline** unless the explicit automatic-test toggle is enabled. Preview captures the selected strategy at animation start, so changing buttons does not mutate an animation already running.

| Strategy | Preparation | Terminal | Diagnostic purpose |
| --- | --- | --- | --- |
| 17.2 Baseline | Power ON → RGB → Preferred | Power ON → RGB → Preferred | Known field-good control |
| 17.2 + Hold | Baseline + 0.75 s steady hold | Baseline | Separate preparation flash from waveform start |
| No End Power | Baseline | Preferred only | Test whether terminal Power/RGB causes end flash |
| No End Commit | Baseline | No extra write | Test whether any terminal write causes end flash |
| Already-On Minimal | No preparation write | Preferred only | Test whether preparation causes start flash |
| 18 No-Flash | RGB → Preferred → Power ON → Preferred | Preferred only | Reproduce historical v90.18 experiment for comparison |

`Preview BLEDIM Only` runs only enabled/ON/controllable BLEDIM devices. Center/Lotus remains unchanged.
