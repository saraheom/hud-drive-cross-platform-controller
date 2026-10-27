"""v24.42: executable Swift coverage policy and guarded road-identity regression.

Exercises production Foundation-only Swift functions, and checks that the iOS
integration does not mix query-center coordinates with actual GPS or delete
older geographic tiles when fetching the next area.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import re
import zipfile

import pytest

ROOT = Path(__file__).resolve().parents[1]
VEH = ROOT / 'ios/HUDController/Vehicle'
ENGINE = (VEH / 'OriginalSpeedLimitEngine.swift').read_text()
CANVAS = (ROOT / 'ios/HUDController/MapMode/HudMapModeCanvas.swift').read_text()


def test_multi_tile_cache_and_prefetch_are_wired_without_single_center_rejection():
    assert 'currentNavActiveAreaRadiusMeters: CLLocationDistance = 385' in ENGINE
    assert 'let nearbyAreas = currentNavDiskAreas.compactMap' in ENGINE
    assert 'for nearbyArea in nearbyAreas {' in ENGINE
    assert 'currentNavRoads = elements.compactMap(Self.makeCurrentNavRoad)' in ENGINE
    assert 'currentNavDiskAreas.insert(CurrentNavDiskArea(' in ENGINE
    assert 'CurrentNavCoveragePlanner.fetchCenter(' in ENGINE
    assert 'currentNavAheadUncoveredThresholdMeters: CLLocationDistance = 190' in ENGINE
    assert 'nearestCenterMeters <= currentNavAheadUncoveredThresholdMeters' in ENGINE
    assert 'recordCurrentNavArea(at: target, elements: primary.elements)' in ENGINE
    assert 'if let live = currentNavLatestValidLocation' in ENGINE
    assert 'location.distance(from: queryLocation) > 265' not in ENGINE
    assert 'currentNavDiskAreas.count > currentNavMaximumCachedAreas' in ENGINE
    assert 'currentNavCacheExpirySeconds: TimeInterval = 72 * 3600' in ENGINE
    assert 'sourceMode == .currentNav { currentNavLatestValidLocation = location }' in ENGINE
    # When moving, optional slow secondary query cannot hold primary acquisition.
    assert 'originalDistance <= 80 else { return }' in ENGINE


def test_posted_limit_needs_same_road_and_real_geometry():
    assert 'let semanticMatch = Self.routeRoadMatches(navRoad, name: candidate.name, reference: candidate.reference)' in ENGINE
    assert 'CurrentNavRoadMatchPolicy.eligible(' in ENGINE
    assert 'no borrowed highway limit' in ENGINE
    assert 'guard let mph = directMph ?? connectedMph, mph > 0 else' in ENGINE
    assert 'cached explicit OSM limit; warning off until refreshed' in ENGINE
    assert 'sourceMode == .currentNav, limit == nil, currentSpeedLimitMph > 0' in ENGINE
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded(at: location, force: force)' in ENGINE


def test_original_current_transport_preserved():
    assert 'https://overpass-api.de/api/interpreter' in ENGINE
    assert 'let query = "[out:json];way[maxspeed][highway](around:400,' in ENGINE
    assert 'URLSession.shared.data(from: url)' in ENGINE
    assert 'CurrentNavOSMTransport.download(url: url)' in ENGINE
    assert 'currentNavPrimaryQueryRadiusMeters = 400' in ENGINE


def test_native_swift_query_lookahead_across_simulated_20_minute_drive():
    if not shutil.which('swiftc'):
        pytest.skip('Swift compiler unavailable')
    swift = r'''
import Foundation
// Start in Philadelphia, heading East along a model straight road.
let lat = 39.9600, lon = -75.1800
let zero = CurrentNavCoveragePlanner.fetchCenter(latitude:lat, longitude:lon, courseDegrees:-1, speedMetersPerSecond:0)
precondition(abs(zero.latitude-lat) < 1e-12 && abs(zero.longitude-lon) < 1e-12)
let forward = CurrentNavCoveragePlanner.fetchCenter(latitude:lat, longitude:lon, courseDegrees:90, speedMetersPerSecond:11.0)
precondition(abs(CurrentNavCoveragePlanner.distanceMeters(forward, .init(latitude:lat, longitude:lon)) - 270) < 1.0)
precondition(abs(forward.latitude - lat) < 0.00002)
let west = CurrentNavCoveragePlanner.fetchCenter(latitude:lat, longitude:lon, courseDegrees:270, speedMetersPerSecond:11.0)
precondition(west.longitude < lon && forward.longitude > lon)
let original: CurrentNavCoveragePlanner.Point = .init(latitude:lat, longitude:lon)
let farAway: CurrentNavCoveragePlanner.Point = .init(latitude:lat+0.009, longitude:lon)
precondition(CurrentNavCoveragePlanner.nearestCenterDistanceMeters(point:original, centers:[]) == .infinity)
precondition(CurrentNavCoveragePlanner.nearestCenterDistanceMeters(point:original, centers:[farAway]) > 900)
// Simulate 20min at 11m/s on a straight projected path. Every 8 seconds
// inspect the real production prefetch policy; a tile of 400m radius can
// supply the current roadway while prefetch targets move >=190m beyond it.
var centers: [CurrentNavCoveragePlanner.Point] = []
var priorFetchedAt: Double = -1e9
var lastAcceptedCenter: CurrentNavCoveragePlanner.Point? = nil
var successes = 0
for second in stride(from:0, through:1200, by:8) {
  let travelled = Double(second) * 11.0
  let car = CurrentNavCoveragePlanner.Point(latitude: lat, longitude:lon + travelled/(111_320*cos(lat * .pi / 180)))
  let ahead = CurrentNavCoveragePlanner.fetchCenter(latitude:car.latitude, longitude:car.longitude, courseDegrees:90, speedMetersPerSecond:11)
  let near = CurrentNavCoveragePlanner.nearestCenterDistanceMeters(point:ahead, centers:centers)
  if near > 190 && Double(second) - priorFetchedAt >= 8 {
    centers.append(ahead)
    successes += 1
    lastAcceptedCenter = ahead
    priorFetchedAt = Double(second)
  }
  // A successful 400m query centered 270m forward always includes the
  // current GPS point at acquisition, while identity matching remains separate.
  precondition(CurrentNavCoveragePlanner.nearestCenterDistanceMeters(point:car, centers:centers) < 390)
}
precondition(successes >= 25)
precondition(centers.count == successes)
// Name+geometry policy must STILL refuse any nearby expressway.
precondition(!CurrentNavRoadMatchPolicy.eligible(
  semanticRoadNameMatch:false, distanceMeters:2, gpsAccuracyMeters:7,
  moving:true, headingErrorDegrees:0))
precondition(CurrentNavRoadMatchPolicy.eligible(
  semanticRoadNameMatch:true, distanceMeters:4, gpsAccuracyMeters:7,
  moving:true, headingErrorDegrees:4))
print("v24.42 native Swift coverage and anti-highway replay PASS; centers=\(successes)")
'''
    with tempfile.TemporaryDirectory() as t:
        main = Path(t) / 'main.swift'
        main.write_text(swift)
        executable = Path(t) / 'coverage'
        result = subprocess.run(['swiftc', str(VEH / 'CurrentNavCoveragePlanner.swift'), str(VEH / 'CurrentNavRoadMatchPolicy.swift'), str(main), '-o', str(executable)], capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, result.stderr
        run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
        assert run.returncode == 0, run.stderr + run.stdout
        assert 'PASS' in run.stdout
        print(run.stdout)


def test_uturn_remains_approved_artwork_with_three_weight_variants():
    assert 'Image(approvedUTurnAssetName)' in CANVAS
    assert '.frame(width: 37, height: 40)' in CANVAS
    assert 'MapModeApprovedUTurnThin' in CANVAS
    assert 'MapModeApprovedUTurnRegular' in CANVAS
    assert 'MapModeApprovedUTurnBold' in CANVAS
    from PIL import Image
    base = ROOT / 'ios/HUDController/Assets.xcassets'
    areas = []
    for name in ('Thin', 'Regular', 'Bold'):
        path = base / f'MapModeApprovedUTurn{name}.imageset' / f'MapModeApprovedUTurn{name}.png'
        with Image.open(path) as image:
            assert image.size == (640, 687)
            areas.append(sum(1 for a in image.convert('RGBA').getchannel('A').getdata() if a > 200))
    assert areas[0] < areas[1] < areas[2]
