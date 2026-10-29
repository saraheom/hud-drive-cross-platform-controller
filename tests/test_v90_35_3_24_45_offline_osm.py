"""v24.45: offline-first Philly OSM bundle acquisition and exact matcher contracts.

The fixture tests code paths, not a claim that this runtime downloaded city data.
The TestFlight workflow must fetch the actual source dataset during its build.
"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import yaml

ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
BUNDLE = ROOT / 'ios/HUDController/Vehicle/CurrentNavOfflineOSMIndex.swift'
BUILDER = ROOT / 'tools/build_philadelphia_osm_bundle.py'
FIXTURE = ROOT / 'tests/fixtures_philly_arcgis_osm_test.geojson'


def test_build_hooks_do_not_silently_ship_empty_offline_map():
    text = BUILDER.read_text()
    assert 'len(roads) < 2000 or tag_count < 100' in text
    assert 'refusing TestFlight build' in text
    for name in ['ios-testflight-ambient-ios26.yml', 'ios-testflight.yml', 'ios-adhoc.yml']:
        yml = yaml.safe_load((ROOT / '.github/workflows' / name).read_text())
        steps = next(iter(yml['jobs'].values()))['steps']
        idx = next(i for i, step in enumerate(steps)
                   if step.get('name') == 'Build verified offline Philadelphia OSM road snapshot')
        assert idx < next(i for i, step in enumerate(steps) if step.get('name') == 'Generate project')
        assert 'tools/build_philadelphia_osm_bundle.py' in steps[idx]['run']


def test_original_current_still_isolated():
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded' in ENGINE
    assert 'private func loadCurrentNavOfflineIfNeeded()' in ENGINE
    assert 'currentNavRoads = combined.compactMap(Self.makeCurrentNavRoad)' in ENGINE
    assert 'segments = online.compactMap(Self.makeSegment)' in ENGINE
    assert 'currentNavNetworkVerifiedWayIDs.contains(chosen.id)' in ENGINE
    assert 'Task.detached(priority: .utility)' in ENGINE
    assert 'CurrentNavRoadMatchPolicy.eligible(' in ENGINE
    assert 'let semanticMatch = Self.routeRoadMatches(navRoad, name: candidate.name, reference: candidate.reference)' in ENGINE


def test_native_offline_index_and_mismatched_expressway():
    if not shutil.which('swiftc'):
        return
    with tempfile.TemporaryDirectory() as folder:
        directory = Path(folder)
        output = directory / 'philly.json'
        run = subprocess.run(['python', str(BUILDER), '--fixture', str(FIXTURE),
                              '--output', str(output)], capture_output=True, text=True, timeout=12)
        assert run.returncode == 0, run.stderr
        data = json.loads(output.read_text())
        assert len(data['roads']) == 3
        assert {v['maxspeedKmh'] for v in data['roads']} == {None, 40, 80}
        (directory / 'main.swift').write_text('''
import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let index = try CurrentNavOfflineOSMIndex.load(data: data)
precondition(index.roadCount == 3 && index.speedTaggedCount == 2)
let nearby = index.nearby(latitude: 39.989, longitude: -75.183)
precondition(nearby.contains { $0.name == "Ridge Avenue" && $0.maxspeedKmh == 40 })
precondition(nearby.contains { $0.name == "Schuylkill Expressway" && $0.maxspeedKmh == 80 })
precondition(index.nearby(latitude: 40.08, longitude: -75.5).isEmpty)
// A closer expressway may not supply the speed for a named city street.
precondition(CurrentNavRoadIdentity.routeRoadMatches("Ridge Ave", name: "Ridge Avenue", reference: nil))
precondition(!CurrentNavRoadIdentity.routeRoadMatches("Ridge Ave", name: "Schuylkill Expressway", reference: "I 76"))
precondition(!CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch: false,
    distanceMeters: 2, gpsAccuracyMeters: 4, moving: true,
    headingErrorDegrees: 0, activelyTurning: false))
print("OFFLINE_NATIVE_REPLAY_PASS")
''')
        compile_run = subprocess.run(['swiftc', str(BUNDLE),
                                      str(ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift'),
                                      str(ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadMatchPolicy.swift'),
                                      str(directory / 'main.swift'), '-o', str(directory / 'runner')],
                                     capture_output=True, text=True, timeout=45)
        assert compile_run.returncode == 0, compile_run.stderr
        result = subprocess.run([str(directory / 'runner'), str(output)],
                                capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert 'OFFLINE_NATIVE_REPLAY_PASS' in result.stdout
