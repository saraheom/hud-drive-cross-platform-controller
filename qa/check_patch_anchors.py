#!/usr/bin/env python3
"""Verify the self-contained application produces the intended postconditions.
The actual reviewed GitHub base blob is checked at apply time.
"""
from pathlib import Path
import ast
import importlib.util

root = Path(__file__).resolve().parents[1]
script = root / 'apply_to_repo.py'
spec = importlib.util.spec_from_file_location('hud_patch', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

syntax = ast.parse(script.read_text())
anchors=[]
for node in ast.walk(syntax):
    if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='replace_once':
        assert len(node.args)>=4
        assert isinstance(node.args[1],ast.Constant)
        anchors.append(node.args[1].value)
assert len(anchors)==11, f'patch anchor count changed: {len(anchors)}'
source='\n\n// synthetic test separator\n\n'.join(anchors)
modified=module.apply(source)
for key in ('ADOPT_CURRENT_VIEWER','AUTO_REJOIN attempt=',
            'JOIN_ABORT current viewer already healthy',
            'automaticStartFailure = "iPhone JPEG relay prewarm failed"',
            'startHUDU2WAutoReconciliation(reason: "BLE transport ready")'):
    assert key in modified, key
assert source!=modified
assert module.git_blob_sha(b'hello\n')=='ce013625030ba8dba906f756967f9e9ca394464a', 'Git blob hash mismatch'
print(f'PASS: {len(anchors)} source substitutions and required postconditions')
