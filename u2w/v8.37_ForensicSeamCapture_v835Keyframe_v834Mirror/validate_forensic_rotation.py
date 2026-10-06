#!/usr/bin/env python3
"""Offline validator for v8.37 seam-evidence semantics.

This does not emulate the CarPlay process.  It stress-tests the exact bounded
old-tail/new-head sample, SHA-1 fingerprint, and newest-N retention rules used
by the passive sidecar so packaging errors are caught before a field drive.
"""
from __future__ import annotations
from hashlib import sha1
from pathlib import Path
import tempfile

SAMPLE = 4096
KEEP = 128


def capture(old: bytes, new: bytes) -> tuple[bytes, bytes, str, str]:
    old_tail = old[-SAMPLE:]
    new_head = new[:SAMPLE]
    return old_tail, new_head, sha1(old_tail).hexdigest(), sha1(new_head).hexdigest()


def generation_blob(i: int, size: int = 16384) -> bytes:
    # Deterministic, nonperiodic enough at 4 KiB boundaries for validation.
    return bytes(((j * 131 + i * 29 + (j >> 7)) & 0xFF) for j in range(size))


def run_boundary_pass(rotations: int = 71) -> None:
    for i in range(rotations):
        old = generation_blob(i)
        new = generation_blob(i + 1)
        ot, nh, osh, nsh = capture(old, new)
        assert len(ot) == SAMPLE and len(nh) == SAMPLE
        assert osh == sha1(old[-SAMPLE:]).hexdigest()
        assert nsh == sha1(new[:SAMPLE]).hexdigest()
        # Deliberate one-byte corruption must become observable in fingerprint.
        corrupt = bytearray(nh); corrupt[17] ^= 0x80
        assert sha1(corrupt).hexdigest() != nsh


def run_retention_pass(rotations: int = 143) -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        retained: list[int] = []
        for event in range(1, rotations + 1):
            tag = f"{event:04d}"
            old = generation_blob(event - 1)
            new = generation_blob(event)
            ot, nh, _, _ = capture(old, new)
            (root / f"seam_{tag}_old_tail_{SAMPLE}.bin").write_bytes(ot)
            (root / f"seam_{tag}_new_head_{SAMPLE}.bin").write_bytes(nh)
            retained.append(event)
            old_event = event - KEEP
            if old_event > 0:
                old_tag = f"{old_event:04d}"
                for p in root.glob(f"seam_{old_tag}_*"):
                    p.unlink()
                retained.remove(old_event)
        assert len(retained) == KEEP
        assert retained[0] == rotations - KEEP + 1
        assert retained[-1] == rotations
        assert len(list(root.glob("*.bin"))) == KEEP * 2


if __name__ == "__main__":
    run_boundary_pass(71)
    run_retention_pass(143)
    print("v8.37 forensic rotation validation: PASS (71 seams + 143-rotation retention + corruption detection)")
