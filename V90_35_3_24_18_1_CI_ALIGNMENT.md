# v90.35.3.24.18.1 CI Alignment

This repository is runtime-identical to v90.35.3.24.18. It corrects six legacy XCTest methods (seven assertions) that still encoded superseded v24.14/v24.17 contracts.

Updated XCTest expectations:
- physical Map Mode starts fallback-first and treats MainVideo as an optional live source;
- the physical source label is `physical Map Mode live source (optional)`;
- TCP preparing/waiting is compatible with fallback-first projection;
- repeated VideoToolbox `-8969` hard-resets the decoder/reference state while preserving validated SPS/PPS and TCP, then waits for the next validated IDR;
- the physical compositor uses `freshLiveMapImage` when MainVideo is current and otherwise renders the fallback canvas.

No production Swift source, U2W image, route-guidance behavior, ambient-light behavior, or OBD behavior was changed for this CI alignment.
