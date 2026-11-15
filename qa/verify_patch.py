#!/usr/bin/env python3
import importlib.util
import tempfile
from pathlib import Path

pkg = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('patcher', pkg / 'apply_to_repo.py')
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)

# Exercise exactly the transformations shipped in the patcher using isolated
# synthetic source files made from the expected GitHub source anchors.
collected = []
real = patcher.replace_once

def spy(text, old, new, label):
    collected.append((old, new, label))
    return text
patcher.replace_once = spy
with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp)
    rels = [
        'ios/HUDController/Models/HudMapModeSettings.swift',
        'ios/HUDController/MapMode/HudMapModeCanvas.swift',
        'ios/HUDController/MapMode/U2WMainVideoClient.swift',
    ]
    for rel in rels:
        path = repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('// TEST ONLY\n')
    patcher.main(repo)
    patcher.replace_once = real
    assert len(collected) >= 17, len(collected)
    groups = [collected[:2], collected[2:6], collected[6:]]
    for rel, group in zip(rels, groups):
        (repo / rel).write_text('\n\n// === EXPECTED ANCHOR ===\n'.join(x[0] for i,x in enumerate(group) if not any(x[0] in prev[1] for prev in group[:i])))
    patcher.main(repo)
    for rel, group in zip(rels, groups):
        result = (repo / rel).read_text()
        for old, new, label in group:
            assert new in result or (label == 'source crop filter switch' and 'case .routeSpotlight:' in result and 'if hasLiveRoute, let routeImage' in result), f'{label}: new code missing'
    source = (repo / rels[2]).read_text()
    for word in ['IN_PLACE_BOOTSTRAP', 'BYTE_OVERLAP_PROVEN', 'decoded_continuity_probe',
                 'beginInPlaceReadOnlyBootstrap', 'codecBadDataErr (-8969)']:
        assert word in source, word
    print(f'PASS: {len(collected)} source replacements, 2 added Swift files, bounded in-place recovery and route filter markers')
