#!/usr/bin/env python3
"""Apply November 15 iOS CI regression-contract fix to the actual Git checkout.

Verifies the exact source blobs, updates XCTest contracts for v24.36's genuine
same-TCP decoder behavior, enables CI for all branch pushes, and rolls back if
source-test assertions fail.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

BASE_COMMIT = "ae68a85c2ca15c1bcce484e88b0a4f5546c14866"
OLD_HASHES = {
    "ios/HUDControllerTests/V90352429StartupBootstrapFullCanvasTests.swift": "a79c6ad0f66944044a60af1590bf3cb6e29560bd",
    "ios/HUDControllerTests/V90352431ResourceSafeBackgroundProbeTests.swift": "3be85470597517c1d92c29096089852bcffdf78e",
    "ios/HUDControllerTests/V90352432ProductionMapBackgroundETAWarningTests.swift": "7de6d05832e52d7ffdc52669a5997b39d1fe30a8",
    ".github/workflows/ios-ci.yml": "b043083055f580b7715a0c951df7e60cfd056907",
}
SRC_BOOTSTRAP = "ios/HUDController/MapMode/U2WMainVideoClient.swift"


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def once(content: str, old: str, new: str, path: str) -> str:
    n = content.count(old)
    if n != 1:
        raise RuntimeError(f"{path}: expected one replacement anchor, found {n}: {old[:120]!r}")
    return content.replace(old, new, 1)


def patch(path: str, text: str) -> str:
    if path.endswith("V90352429StartupBootstrapFullCanvasTests.swift"):
        return once(
            text,
            '        XCTAssertTrue(video.contains("continuous_join=YES"))',
            '''        // Byte overlap is not a successfully decoded output frame.
        XCTAssertTrue(video.contains("BYTE_OVERLAP_PROVEN=YES"))
        XCTAssertTrue(video.contains("validated_idr="))
        XCTAssertTrue(video.contains("display recovery requires a real decoded frame"))''',
            path,
        )
    if path.endswith(("V90352431ResourceSafeBackgroundProbeTests.swift",
                       "V90352432ProductionMapBackgroundETAWarningTests.swift")):
        return once(
            text,
            '''        XCTAssertTrue(video.contains("lock-time -12903 detected"))
        XCTAssertTrue(video.contains(#"restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")"#))''',
            '''        // v24.36 handles both codec failures with a bounded recovery
        // coordinator; a healthy raw TCP connection must be preserved.
        XCTAssertTrue(video.contains("kVTInvalidSessionErr (-12903)"))
        XCTAssertTrue(video.contains("codecBadDataErr (-8969)"))
        XCTAssertTrue(video.contains("decoder failure detected scene="))
        XCTAssertTrue(video.contains("IN_PLACE_BOOTSTRAP requested"))
        XCTAssertTrue(video.contains("worker.beginInPlaceReadOnlyBootstrap(reason: reason)"))''',
            path,
        )
    if path == ".github/workflows/ios-ci.yml":
        return once(
            text,
            '''  push:
    paths:
      - "ios/**"
      - ".github/workflows/ios-ci.yml"
      - ".github/workflows/ios-testflight-ambient-ios26.yml"
''',
            '''  # Auto-run after EVERY branch push, including root-level build scripts.
  # Previously, path filters silently skipped hotfix-only commits.
  push:
    branches:
      - "**"
''',
            path,
        )
    raise ValueError(f"Unexpected path: {path}")


def check_production_contract(repo: Path) -> None:
    code = (repo / SRC_BOOTSTRAP).read_text("utf-8")
    mandatory = (
        "IN_PLACE_BOOTSTRAP requested",
        "worker.beginInPlaceReadOnlyBootstrap(reason: reason)",
        "BYTE_OVERLAP_PROVEN=YES",
        "validated_idr=",
        "display recovery requires a real decoded frame",
        "decoder failure detected scene=",
        "kVTInvalidSessionErr (-12903)",
        "codecBadDataErr (-8969)",
    )
    missing = [x for x in mandatory if x not in code]
    if missing:
        raise RuntimeError("Production video contract does not match v24.36: " + ", ".join(missing))


def apply(repo: Path) -> None:
    repo = repo.resolve()
    if not (repo / ".git").exists():
        raise RuntimeError(f"Not a Git checkout: {repo}")
    rev = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                         capture_output=True, text=True).stdout.strip()
    if rev != BASE_COMMIT:
        raise RuntimeError(f"Expected main at {BASE_COMMIT}, found {rev}; pull/reconcile first.")
    check_production_contract(repo)
    old_bytes: dict[Path, bytes] = {}
    new_bytes: dict[Path, bytes] = {}
    for relative, expected_sha in OLD_HASHES.items():
        target = repo / relative
        raw = target.read_bytes()
        # Windows Git may check out CRLF text even when the Git blob uses LF.
        # Validate the canonical Git content but preserve working-tree EOLs.
        canonical = raw.replace(b"\r\n", b"\n")
        actual_sha = blob_sha(canonical)
        if actual_sha != expected_sha:
            raise RuntimeError(f"{relative}: expected blob {expected_sha}, got {actual_sha}; nothing written.")
        old_bytes[target] = raw
        updated = patch(relative, canonical.decode("utf-8"))
        if b"\r\n" in raw:
            updated = updated.replace("\n", "\r\n")
        new_bytes[target] = updated.encode("utf-8")

    try:
        for target, new_data in new_bytes.items():
            target.write_bytes(new_data)
        check_production_contract(repo)
        wf = (repo / ".github/workflows/ios-ci.yml").read_text("utf-8")
        assert '  push:\n    branches:\n      - "**"\n' in wf
        cmd = [sys.executable, str(repo / "scripts/validate_swift_test_source_assertions.py")]
        result = subprocess.run(cmd, cwd=repo, capture_output=True, text=True)
        print(result.stdout, end="")
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr, end="")
            raise RuntimeError("Swift source-test preflight failed. Restoring original files.")
        print("PASS: 4 actual repository files updated; all source contracts passed; push trigger verified.")
        for target in new_bytes:
            print("CHANGED:", target.relative_to(repo))
    except BaseException:
        for target, raw in old_bytes.items():
            target.write_bytes(raw)
        raise


def self_test() -> None:
    old = '        XCTAssertTrue(video.contains("continuous_join=YES"))'
    assert 'BYTE_OVERLAP_PROVEN=YES' in patch("ios/HUDControllerTests/V90352429StartupBootstrapFullCanvasTests.swift", old)
    old = '''        XCTAssertTrue(video.contains("lock-time -12903 detected"))
        XCTAssertTrue(video.contains(#"restartWorkerWithReadOnlyBootstrap(reason: "lock-time VideoToolbox invalid session -12903")"#))'''
    for fn in ("V90352431ResourceSafeBackgroundProbeTests.swift", "V90352432ProductionMapBackgroundETAWarningTests.swift"):
        new = patch("ios/HUDControllerTests/" + fn, old)
        assert new.count("IN_PLACE_BOOTSTRAP requested") == 1
        assert "lock-time -12903 detected" not in new
    old = '''  push:
    paths:
      - "ios/**"
      - ".github/workflows/ios-ci.yml"
      - ".github/workflows/ios-testflight-ambient-ios26.yml"
'''
    new = patch(".github/workflows/ios-ci.yml", old)
    assert 'push:\n    branches:\n      - "**"' in new
    assert "paths:" not in new
    print("PASS: 4/4 patch transformation checks")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
    elif args.repo:
        try:
            apply(args.repo)
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            sys.exit(1)
    else:
        ap.error("Specify --repo PATH or --self-test")
