"""v24.39 road-data acquisition safeguards / executable near-turn geometry tests.

These are deliberately limited to source contracts and the actual platform-neutral
Swift road geometry. iOS network and filesystem still require device validation.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
POLICY = ROOT / "ios/HUDController/Vehicle/CurrentNavRoadMatchPolicy.swift"


def test_current_alone_still_has_original_lookup():
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded' in ENGINE
    assert 'way[maxspeed][highway](around:400' in ENGINE
    assert 'Self.originalPolygonContains(' in ENGINE


def test_disk_cache_contains_real_geometries_and_bounds():
    assert 'struct Element: Codable' in ENGINE
    assert 'struct Tags: Codable' in ENGINE
    assert 'struct Coordinate: Codable' in ENGINE
    assert 'private struct CurrentNavDiskArea: Codable' in ENGINE
    assert 'let elements: [Element]' in ENGINE
    assert 'applicationSupportDirectory' in ENGINE
    assert 'CurrentNavOSMRoadCache-v1.json' in ENGINE
    assert 'data.write(to: url, options: .atomic)' in ENGINE
    assert 'currentNavMaximumCachedAreas = 128' in ENGINE
    assert 'currentNavCacheExpirySeconds: TimeInterval = 72 * 3600' in ENGINE
    assert 'currentNavActiveAreaRadiusMeters: CLLocationDistance = 240' in ENGINE
    assert 'activateCurrentNavCachedArea(at: location)' in ENGINE
    assert 'currentNavRoads = elements.compactMap(Self.makeCurrentNavRoad)' in ENGINE


def test_lightweight_query_and_respectful_retry():
    assert 'currentNavQueryRadiusMeters = 260' in ENGINE
    assert 'way[maxspeed][highway](around:' in ENGINE
    assert 'way[highway][name](around:' in ENGINE
    assert 'out tags geom;' in ENGINE
    assert 'https://overpass.private.coffee/api/interpreter' in ENGINE
    assert 'https://overpass-api.de/api/interpreter' in ENGINE
    assert 'currentNavOverpassEndpointIndex = (currentNavOverpassEndpointIndex + 1)' in ENGINE
    assert 'currentNavInitialFailureBackoffSeconds: TimeInterval = 20' in ENGINE
    assert 'currentNavMaximumFailureBackoffSeconds: TimeInterval = 5 * 60' in ENGINE
    assert 'pow(2.0, Double(currentNavFailureCount - 1))' in ENGINE
    assert 'currentNavSuccessRefreshSeconds: TimeInterval = 30 * 60' in ENGINE
    assert 'guard !tagged.isEmpty else { throw URLError(.cannotParseResponse) }' in ENGINE


def test_no_highway_borrowing_no_stale_warning():
    assert 'let semanticMatch = Self.routeRoadMatches(navRoad, name: candidate.name, reference: candidate.reference)' in ENGINE
    assert 'CurrentNavRoadMatchPolicy.eligible(' in ENGINE
    assert 'guard let winner = scored.first else {' in ENGINE
    assert 'no borrowed highway limit' in ENGINE
    assert 'currentNavMatchFresh = currentNavQueryAt.map {' in ENGINE
    assert 'currentNavFreshWarningSeconds: TimeInterval = 30 * 60' in ENGINE
    assert 'cached explicit OSM limit; warning off until refreshed' in ENGINE
    assert 'currentNavNetworkVerifiedWayIDs.contains(chosen.id)' in ENGINE
    assert 'connected same-road speed; warning off' in ENGINE
    assert 'stale active navigation; no cross-road fallback' in ENGINE
    assert 'symmetricDirectionalSpeed' in ENGINE
    assert 'clearDisplayedLimit(reason: "CarPlay street changed to' in ENGINE


def test_diagnostics_categorize_failure():
    assert 'no cached OSM roads at this location' in ENGINE
    assert 'named road geometry/heading rejected' in ENGINE
    assert 'CarPlay street absent from cached OSM road names' in ENGINE
    assert 'posted speed unavailable' in ENGINE
    assert 'heading=' in ENGINE
    assert 'retryBackoff=' in ENGINE
    assert 'cachedAreas=' in ENGINE


def test_real_swift_geometry_turn_tolerance_keeps_strict_street_identity():
    if not shutil.which("swiftc"):
        import pytest
        pytest.skip("swiftc missing")
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        main = folder / "main.swift"
        main.write_text('''
import Foundation
// Named road just 9m from GPS. Immediately after a turn, course and
// OSM polyline can disagree for one or two measurements.
precondition(CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch:true, distanceMeters:9, gpsAccuracyMeters:9,
 moving:true, headingErrorDegrees:79))
precondition(CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch:true, distanceMeters:9, gpsAccuracyMeters:9,
 moving:true, headingErrorDegrees:101, activelyTurning:true))
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch:true, distanceMeters:9, gpsAccuracyMeters:9,
 moving:true, headingErrorDegrees:101, activelyTurning:false))
// An expressway 2m away must never steal another street's limit.
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch:false, distanceMeters:2, gpsAccuracyMeters:15,
 moving:true, headingErrorDegrees:3, activelyTurning:true))
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch:true, distanceMeters:80, gpsAccuracyMeters:10,
 moving:true, headingErrorDegrees:10, activelyTurning:true))
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch:true, distanceMeters:20, gpsAccuracyMeters:10,
 moving:true, headingErrorDegrees:98, activelyTurning:true))
print("Swift v24.39 turning/road identity tests PASSED")
''')
        target = folder / "test"
        compiled = subprocess.run(["swiftc", str(POLICY), str(main), "-o", str(target)], capture_output=True, text=True, timeout=45)
        assert compiled.returncode == 0, compiled.stderr
        executed = subprocess.run([str(target)], capture_output=True, text=True, timeout=5)
        assert executed.returncode == 0, executed.stderr
        assert "PASSED" in executed.stdout
