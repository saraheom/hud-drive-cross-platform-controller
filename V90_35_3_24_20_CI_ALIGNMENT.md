# v90.35.3.24.20 CI alignment

Legacy source-contract tests that described v8.32 as the current relay were updated to the v24.20/v8.33 contract. The historical v8.32 handshake/recovery code remains recognized for rollback compatibility.

New coverage checks the v8.33 lossless mirror invariants:

- atomic full-buffer rotation;
- fallback append instead of byte loss;
- write-all mirror semantics;
- vectored mirroring limited to the real returned byte count;
- exact v8.31 raw relay hash;
- no source reacquisition, large checkpoint/GOP cache, autostart, or AppleCarPlay process control;
- a model demonstrating the old prefix-loss behavior and byte-identical reconstruction under the new atomic rotation.
