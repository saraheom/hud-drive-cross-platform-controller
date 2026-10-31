#!/usr/bin/env python3
"""Check literal Swift XCTest source-text assertions before running Xcode.

Only static direct `XCTAssertTrue/False(variable.contains("literal"))` checks are
verified. Dynamic assertions and behavioral tests remain XCTest's responsibility.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
FUNCTION = re.compile(r"\bfunc\s+(test\w+)\s*\(")
SOURCE = re.compile(r'\blet\s+(\w+)\s*=\s*try\s+source\("([^"]+)"\)')
ASSERTION = re.compile(
    r'XCTAssert(True|False)\(\s*(\w+)\.contains\((#?)"((?:\\.|[^"\\])*)"\3\)\s*\)'
)


def check_source_assertions(root: Path = ROOT):
    count = 0
    dynamic = 0
    errors = []
    for file in sorted((root / "ios" / "HUDControllerTests").glob("*.swift")):
        source = file.read_text(encoding="utf-8")
        functions = list(FUNCTION.finditer(source))
        for i, fun in enumerate(functions):
            body = source[fun.start():functions[i + 1].start() if i + 1 < len(functions) else len(source)]
            bindings = {}
            for item in SOURCE.finditer(body):
                relative = item.group(2)
                candidates = (root / "ios" / relative, root / relative)
                path = next((p.resolve() for p in candidates if p.is_file()), None)
                if path is not None:
                    bindings[item.group(1)] = path
            for match in ASSERTION.finditer(body):
                expected, var, raw, literal = match.groups()
                if var not in bindings:
                    continue
                if not raw and r"\(" in literal:
                    dynamic += 1
                    continue
                try:
                    value = literal if raw else json.loads('"' + literal + '"')
                except ValueError:
                    dynamic += 1
                    continue
                present = value in bindings[var].read_text(encoding="utf-8", errors="replace")
                count += 1
                if present != (expected == "True"):
                    errors.append(f"{file.name}: {fun.group(1)} expected contains={expected} "
                                  f"for {var} / {value!r} in {bindings[var].relative_to(root)}")
    return count, dynamic, errors


if __name__ == "__main__":
    count, dynamic, errors = check_source_assertions()
    print(f"Swift source-test contracts: {count} static assertions checked, "
          f"{dynamic} dynamic assertions left to XCTest, {len(errors)} mismatches")
    for item in errors:
        print("ERROR:", item, file=sys.stderr)
    if count < 500:
        print("ERROR: unexpectedly few assertions scanned", file=sys.stderr)
    sys.exit(1 if errors or count < 500 else 0)
