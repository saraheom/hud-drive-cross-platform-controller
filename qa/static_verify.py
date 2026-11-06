#!/usr/bin/env python3
from pathlib import Path
import ast
import subprocess
import tempfile
import importlib.util

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('apply_to_repo', root/'apply_to_repo.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
# Extract patch-injected complete method from the source-code string literal,
# validate parsing without needing Apple SDK or the 210KB original AppState.
tree = ast.parse((root/'apply_to_repo.py').read_text())
fragments = []
for node in ast.walk(tree):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        if '    private func startHUDU2WAutoReconciliation(reason: String) {' in node.value:
            fragments.append(node.value)
assert len(fragments)==1, 'Expected exact one inserted reconciling implementation'
source = fragments[0]
assert 'currentSessionReady' in source
assert 'HUDMapModeAutoRejoinPolicy.shouldRetry(' in source
assert 'scheduleHUDU2WAutomaticJoinRecovery(' in source
assert 'mainVideo.stop' not in source and 'mainVideo.start' not in source
assert 'u2whud-start.cgi' not in source
assert 'CGI status unavailable; no recovery action' in source
method = source.split('    private func startHUDU2WDisplayHealthMonitor() {')[0]
with tempfile.TemporaryDirectory() as temp:
    stub = Path(temp)/'RejoinSyntax.swift'
    stub.write_text('import Foundation\n@MainActor\nfinal class AppState {\n'+method+'\n}\n')
    result=subprocess.run(['swiftc','-frontend','-parse',str(stub)],text=True,capture_output=True)
    assert result.returncode==0, result.stderr
print('PASS: Swift syntax parse of full injected reconciling method')
print('PASS: independent viewer recovery, no MainVideo restart/adapter restart')
