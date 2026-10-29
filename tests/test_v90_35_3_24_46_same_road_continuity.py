"""v24.46: compile/run the production Swift policy, including a synthetic
five-minute MLK Drive trip derived from the Oct 29 log's named-road decisions.
This checks decision rules, not unseen posted roadside signs.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'ios/HUDController/Vehicle/CurrentNavSameRoadContinuity.swift'
IDENTITY = ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift'
MATCH = ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadMatchPolicy.swift'
ENGINE = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
LOG = Path('/mnt/data/HUD_2026-10-28_22-45-51.log')


def test_same_road_display_only_and_conflict_rules_are_wired():
    assert 'CurrentNavSameRoadContinuity.verified(' in ENGINE
    assert 'CurrentNavSameRoadContinuity.advance(' in ENGINE
    assert 'currentNavContinuityAnchor = nil' in ENGINE
    assert 'CONTINUITY_DISPLAY_ONLY' in ENGINE
    assert 'currentNavMatchFresh = false' in ENGINE
    assert 'currentNavDisplayHold = true' in ENGINE
    assert 'contradictoryPostedLimitNearby: contradictoryPostedSpeed' in ENGINE
    assert 'limit == nil || currentNavContinuityCarried' in ENGINE
    assert 'private let currentNavHoldMaxSeconds: TimeInterval = 12.0' in ENGINE
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded' in ENGINE


def test_oct29_log_has_exact_evidence_for_the_new_policy():
    if not LOG.exists():
        return
    txt = LOG.read_text(errors='replace')
    assert re.search(r'ACCEPT current=Martin Luther King Jr Dr matched=Martin Luther King Junior Drive .*speed=25mph evidence=direct_OSM', txt)
    assert re.search(r'UNKNOWN current=Martin Luther King Jr Dr matched=Martin Luther King Junior Drive .*untagged=1', txt)
    assert 'Schuylkill Expressway' in txt


def test_compiled_swift_end_to_end_continuity_and_antihighway():
    if not shutil.which('swiftc'):
        return
    source = r'''
import Foundation
let start = Date(timeIntervalSince1970: 1_000_000)
func check(_ yes: Bool, _ message: String) { precondition(yes, message) }
let road = CurrentNavRoadIdentity.normalizedRoadPhrase("Martin Luther King Jr Dr")
check(road == CurrentNavRoadIdentity.normalizedRoadPhrase("Martin Luther King Junior Drive"), "MLK normalization")
check(!CurrentNavRoadIdentity.routeRoadMatches("Martin Luther King Jr Dr", name: "Schuylkill Expressway", reference: "I 76"), "no highway borrowing")
check(CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch: true, distanceMeters: 3.6,
    gpsAccuracyMeters: 5, moving: true, headingErrorDegrees: 2), "real MLK-style geometry")
check(!CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch: false, distanceMeters: 1.0,
    gpsAccuracyMeters: 5, moving: true, headingErrorDegrees: 0), "closer expressway still ineligible")
var state = CurrentNavSameRoadContinuity.verified(identity: road, speedMph: 25,
    latitude: 39.98, longitude: -75.20, now: start)!
// Recorded drive: actual MLK Drive matching kept finding untagged ways for
// several minutes. Reconstruct GPS samples along the SAME road at 25 mph.
for t in stride(from: 1, through: 300, by: 1) {
    let lat = 39.98 + Double(t) * 0.0001
    let result = CurrentNavSameRoadContinuity.advance(state, roadIdentity: road,
        latitude: lat, longitude: -75.20,
        now: start.addingTimeInterval(Double(t)),
        matchedSameRoadGeometry: true, contradictoryPostedLimitNearby: false)
    check(result != nil, "should bridge valid five-minute same-road untagged stretch: \(t)")
    state = result!
}
check(state.speedMph == 25, "carried verified 25")
check(state.travelledMeters > 3200 && state.travelledMeters < 3500, "actual cumulative metres")
check(state.explicitlyVerifiedAt == start, "carry must not refresh original posted evidence")
let time = start.addingTimeInterval(302)
check(CurrentNavSameRoadContinuity.advance(state, roadIdentity: "north 34th street",
    latitude: 39.99, longitude: -75.20, now: time,
    matchedSameRoadGeometry: true, contradictoryPostedLimitNearby: false) == nil,
    "road name change disarms continuity")
check(CurrentNavSameRoadContinuity.advance(state, roadIdentity: road,
    latitude: 39.99, longitude: -75.20, now: time,
    matchedSameRoadGeometry: false, contradictoryPostedLimitNearby: false) == nil,
    "CarPlay street name only is NOT sufficient")
check(CurrentNavSameRoadContinuity.advance(state, roadIdentity: road,
    latitude: 39.99, longitude: -75.20, now: time,
    matchedSameRoadGeometry: true, contradictoryPostedLimitNearby: true) == nil,
    "conflicting tagged limit vetoes inherited speed")
check(CurrentNavSameRoadContinuity.advance(state, roadIdentity: road,
    latitude: 39.99, longitude: -75.20, now: start.addingTimeInterval(721),
    matchedSameRoadGeometry: true, contradictoryPostedLimitNearby: false) == nil,
    "12-minute maximum cannot refresh by repeated holding")
check(CurrentNavSameRoadContinuity.advance(state, roadIdentity: road,
    latitude: 40.03, longitude: -75.20, now: start.addingTimeInterval(303),
    matchedSameRoadGeometry: true, contradictoryPostedLimitNearby: false) == nil,
    "teleport rejects a false match")
check(CurrentNavSameRoadContinuity.advance(nil, roadIdentity: road,
    latitude: 39.99, longitude: -75.20, now: time,
    matchedSameRoadGeometry: true, contradictoryPostedLimitNearby: false) == nil,
    "no guessed speed without explicit anchor")
// Same road with explicitly posted 35mph must create a NEW anchor rather than
// continuing an earlier 25mph display.
let newAnchor = CurrentNavSameRoadContinuity.verified(identity: road, speedMph: 35,
    latitude: 39.99, longitude: -75.20, now: time)!
check(newAnchor.speedMph == 35 && newAnchor.explicitlyVerifiedAt == time, "new posted speed overrides")
print("NATIVE_CONTINUITY_REPLAY_PASS")
'''
    with tempfile.TemporaryDirectory() as temp:
        swift = Path(temp) / 'main.swift'
        swift.write_text(source)
        binpath = Path(temp) / 'runner'
        result = subprocess.run(['swiftc', str(POLICY), str(IDENTITY), str(MATCH), str(swift),
                                '-o', str(binpath)], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, result.stderr
        run = subprocess.run([str(binpath)], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, run.stderr
        assert 'NATIVE_CONTINUITY_REPLAY_PASS' in run.stdout
