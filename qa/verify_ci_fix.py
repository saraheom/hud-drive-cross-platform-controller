"""Offline regression on the *real packaged patcher* with simulated CI-failing files."""
from pathlib import Path
import importlib.util
import shutil
import tempfile
import subprocess

root = Path(__file__).resolve().parents[1]

def load(path, name):
    spec=importlib.util.spec_from_file_location(name, path)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

old=load(root/'apply_to_repo.py', 'original_hotfix_patch')
fix=load(root/'apply_ci_fix.py', 'ci_fix_installer')
recorded=[]
original_replace=old.replace_once
old.replace_once=lambda s,o,n,label: (recorded.append((o,n,label)) or s)
with tempfile.TemporaryDirectory() as tmp:
    shim=Path(tmp)
    for p in fix.SOURCE_HASHES:
        file=shim/p
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text('// placeholder\n', encoding='utf8')
    old.main(shim)
old.replace_once=original_replace
assert len(recorded)==22, len(recorded)

with tempfile.TemporaryDirectory() as tmp:
    repo=Path(tmp)
    (repo/'.git').mkdir()
    file_groups=[
        ('ios/HUDController/Models/HudMapModeSettings.swift',recorded[:2]),
        ('ios/HUDController/MapMode/HudMapModeCanvas.swift',recorded[2:6]),
        ('ios/HUDController/MapMode/U2WMainVideoClient.swift',recorded[6:]),
    ]
    fake_hashes={}
    for name, group in file_groups:
        path=repo/name
        path.parent.mkdir(parents=True, exist_ok=True)
        # Do not put any old anchor that was introduced by an earlier replacement.
        anchors=[]
        for idx,(before,after,_) in enumerate(group):
            if not any(before in earlier_after for _,earlier_after,_ in group[:idx]):
                anchors.append(before)
        path.write_text('\n// expected unmodified anchor\n'.join(anchors),encoding='utf8')
        fake_hashes[name]=fix.git_blob_sha(path.read_bytes())
    for name in fix.ALREADY_PRESENT:
        dst=repo/name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root/name, dst)
    # Reproduce CI checkout hashes using the exact content of this synthetic fixture.
    fix.SOURCE_HASHES=fake_hashes
    original_which=fix.shutil.which
    fix.shutil.which=lambda command: None if command=='swiftc' else original_which(command)
    fix.main(repo)
    fix.verify_integrations(repo)
    before={name:(repo/name).read_bytes() for name in fake_hashes}
    try:
        fix.main(repo)
    except ValueError as e:
        assert 'Unexpected source revision' in str(e), str(e)
    else:
        raise AssertionError('A second installation must fail closed')
    assert all((repo/name).read_bytes()==before[name] for name in fake_hashes)
    print('PASS: exact-version guard, staging, 22 replacements, 9 integration checks, rollback/no-double-apply')

# Syntax check *new* production code and the test that blocked CI.
if shutil.which('swiftc'):
    subprocess.run(['swiftc','-frontend','-parse',str(root/'ios/HUDController/MapMode/HudRouteSpotlightProcessor.swift'),str(root/'ios/HUDControllerTests/V90352436RouteSpotlightAndRecoveryTests.swift')],check=True)
    print('PASS: new Swift processor/test frontend syntax parsing')
