#!/usr/bin/env python3
"""Restore *all* missing v24.36 integration files on the precise CI-failing tree.

Runs the original patch in a staging directory, validates the five resulting
files, then replaces only the three missing-integration files. Nothing is
written to the requested repo if staging or validation fails.
"""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
SOURCE_HASHES = {
    'ios/HUDController/Models/HudMapModeSettings.swift': '7dba9eaa9589bf3e8764ccd23e2c303481acf493',
    'ios/HUDController/MapMode/HudMapModeCanvas.swift': '6af7602aec638870cf0887f12cabdb625190ddac',
    'ios/HUDController/MapMode/U2WMainVideoClient.swift': '060200df1ef451aaa03c4621cfcf78ab40879447',
}
ALREADY_PRESENT = {
    'ios/HUDController/MapMode/HudRouteSpotlightProcessor.swift': 'f2153854d50b5e65e7762860cf3978a8c6c04d96',
    'ios/HUDControllerTests/V90352436RouteSpotlightAndRecoveryTests.swift': '4c2a5c0175511bd48c186571e22ad7c96fb4ee8c',
}

def git_blob_sha(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def verify_integrations(target):
    settings = (target / 'ios/HUDController/Models/HudMapModeSettings.swift').read_text('utf-8')
    canvas = (target / 'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text('utf-8')
    video = (target / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text('utf-8')
    required = {
        'Route Spotlight appearance enum': 'case routeSpotlight' in settings,
        'Route Spotlight title': 'Route Spotlight (experimental)' in settings,
        'Route Spotlight canvas rendering': 'case .routeSpotlight:' in canvas,
        'Route Spotlight processor call': 'HudRouteSpotlightProcessor.render(image)' in canvas,
        'Route Spotlight navigation gate': 'hasLiveRoute: snapshot.hasLiveRoute' in canvas,
        'Same-TCP codec recovery': 'beginInPlaceReadOnlyBootstrap' in video,
        'Byte overlap is not frame readiness': 'BYTE_OVERLAP_PROVEN' in video,
        'Decoder continuity evidence': 'decoded_continuity_probe' in video,
        'Parser quarantine on recovery': 'quarantineReferenceChainUntilIDR()' in video,
    }
    failed = [name for name, passed in required.items() if not passed]
    if failed:
        raise ValueError('Incomplete integration after patch: ' + ', '.join(failed))
    print('PASS: 9 cross-file integration checks')

def main(repo):
    repo = repo.resolve()
    if not (repo / '.git').exists():
        raise ValueError(f'Not a Git checkout: {repo}')
    for name, sha in {**SOURCE_HASHES, **ALREADY_PRESENT}.items():
        path = repo / name
        if not path.is_file():
            raise FileNotFoundError(f'Required file is missing: {name}')
        got = git_blob_sha(path.read_bytes())
        if got != sha:
            raise ValueError(f'Unexpected source revision in {name}: {got} (expected {sha}). No files changed.')
    print('PASS: all five files match the uploaded CI-failing GitHub source versions')

    with tempfile.TemporaryDirectory(prefix='hud_ci_fix_') as temp:
        stage = Path(temp)
        (stage / 'ios/HUDController').mkdir(parents=True)
        for rel in {**SOURCE_HASHES, **ALREADY_PRESENT}:
            source = repo / rel
            dest = stage / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
        # The v24.36 patch is run entirely on temporary staged copies.
        spec = importlib.util.spec_from_file_location('hud_v2436_original_patcher', ROOT / 'apply_to_repo.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.main(stage)
        verify_integrations(stage)
        for rel, sha in ALREADY_PRESENT.items():
            if git_blob_sha((stage / rel).read_bytes()) != sha:
                raise ValueError(f'Existing test/processor would be changed unexpectedly: {rel}')
        swiftc = shutil.which('swiftc')
        if swiftc:
            paths = [str(stage / rel) for rel in {**SOURCE_HASHES, **ALREADY_PRESENT}]
            subprocess.run([swiftc, '-frontend', '-parse', *paths], check=True)
            print('PASS: Swift frontend syntax parsing (not an iOS SDK build)')
        else:
            print('Swift parser unavailable on this machine; run the macOS/iOS CI workflow after push')

        originals = {rel: (repo / rel).read_bytes() for rel in SOURCE_HASHES}
        replaced = []
        try:
            for rel in SOURCE_HASHES:
                dst = repo / rel
                candidate = stage / rel
                tmp = dst.with_name(dst.name + '.hud-ci-fix-tmp')
                tmp.write_bytes(candidate.read_bytes())
                os.replace(tmp, dst)
                replaced.append(rel)
        except Exception:
            for rel in replaced:
                (repo / rel).write_bytes(originals[rel])
            raise
    print('SUCCESS: restored three missing v24.36 source integrations; existing processor and tests left unchanged')
    print('Next: git diff --check; git add <three files>; git commit; git push; rerun iOS CI')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description='Fix the v24.36 Route Spotlight CI source integration')
    ap.add_argument('--repo', type=Path, required=True)
    args = ap.parse_args()
    try:
        main(args.repo)
    except Exception as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
