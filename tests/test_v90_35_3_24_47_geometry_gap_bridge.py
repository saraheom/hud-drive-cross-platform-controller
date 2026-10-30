"""v24.47 native production Swift replay of the real MLK Drive 22:17:15-31 gap."""
from pathlib import Path
import shutil, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'ios/HUDController/Vehicle/CurrentNavSameRoadContinuity.swift'
IDENTITY = ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadIdentity.swift'
MATCH = ROOT / 'ios/HUDController/Vehicle/CurrentNavRoadMatchPolicy.swift'
ENGINE = (ROOT / 'ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift').read_text()
LOG = Path('/mnt/data/HUD_2026-10-29_17-30-57.log')


def test_engine_wires_bridge_at_no_winner_instead_of_waiting_for_twelve_second_hold():
    assert 'guard let winner = scored.first else {' in ENGINE
    reject_section = ENGINE.split('guard let winner = scored.first else {', 1)[1].split('let chosen = winner.segment', 1)[0]
    assert 'CurrentNavSameRoadContinuity.bridgeUnmappedGap(' in reject_section
    assert reject_section.index('CurrentNavSameRoadContinuity.bridgeUnmappedGap(') < reject_section.index('return heldCurrentNavSpeed')
    assert 'currentNavMatchFresh = false' in reject_section
    assert 'CONTINUITY_GAP_DISPLAY_ONLY' in reject_section
    assert 'warn=0' in reject_section
    assert 'differentRoadGeometryNearby: otherRoadNearby' in reject_section
    assert 'contradictoryPostedLimitNearby: conflictingNamedTag' in reject_section
    assert 'routeTransition: route.isRouteTransition' in reject_section
    assert 'currentNavContinuityCarried = true' in reject_section
    assert 'private let currentNavHoldMaxSeconds: TimeInterval = 12.0' in ENGINE
    # Old Current algorithm is still its own branch.
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE


def test_oct29_drive_exhibits_unmatched_geometry_gap_longer_than_short_hold():
    if not LOG.exists():
        return
    lines = LOG.read_text(errors='replace')
    assert '2026-10-29T22:17:14Z  SPEED CURREN ACCEPT current=Martin Luther King Jr Dr' in lines
    assert '2026-10-29T22:17:23Z  SPEED LIMIT  Cleared stale displayed limit' in lines
    assert '2026-10-29T22:17:31Z  SPEED CURREN ACCEPT current=Martin Luther King Jr Dr' in lines


def test_swift_native_replay_limited_bridge_and_reacquisition():
    if not shutil.which('swiftc'):
        return
    code = r'''
import Foundation
func check(_ ok: Bool, _ msg: String) { precondition(ok, msg) }
let start = Date(timeIntervalSince1970: 1_000_000)
let road = CurrentNavRoadIdentity.normalizedRoadPhrase("Martin Luther King Jr Dr")
let actual = CurrentNavRoadIdentity.normalizedRoadPhrase("Martin Luther King Junior Drive")
check(road == actual, "MLK semantic name normalization")
check(!CurrentNavRoadIdentity.routeRoadMatches("MLK Dr", name: "Schuylkill Expressway", reference: "I 76"), "reject expressway")
// At 22:17:14 the car had explicitly matched MLK 25mph; geometry disappears
// at 22:17:15 and reappears at 22:17:31 (17sec at approx 42 mph).
var anchor = CurrentNavSameRoadContinuity.verified(identity: road, speedMph: 25,
    latitude: 39.984, longitude: -75.200, now: start)!
for second in 1...16 {
    let now = start.addingTimeInterval(Double(second))
    let lat = 39.984 + Double(second) * 0.00017
    let carried = CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor,
        roadIdentity: actual, latitude: lat, longitude: -75.200, now: now,
        freshNavigationStreet: true, routeTransition: false,
        differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false)
    check(carried?.speedMph == 25, "MLK geometry gap at second \(second)")
    check(carried?.lastConfirmedAt == start, "bridge cannot reset last good geometry time")
}
// At 22:17:31 tagged MLK geometry is found again.
let recovered = CurrentNavSameRoadContinuity.advance(anchor, roadIdentity: actual,
    latitude: 39.984 + 17 * 0.00017, longitude: -75.200,
    now: start.addingTimeInterval(17), matchedSameRoadGeometry: true,
    contradictoryPostedLimitNearby: false)
check(recovered?.speedMph == 25, "reacquisition after offline tile seam")
check(recovered!.lastConfirmedAt == start.addingTimeInterval(17), "now geometry-verified")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: road,
    latitude: 39.984 + 31 * 0.00017, longitude: -75.200,
    now: start.addingTimeInterval(31), freshNavigationStreet: true,
    routeTransition: false, differentRoadGeometryNearby: false,
    contradictoryPostedLimitNearby: false) == nil, "unmapped gap cannot continue forever")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: road,
    latitude: 39.994, longitude: -75.200, now: start.addingTimeInterval(15),
    freshNavigationStreet: true, routeTransition: false,
    differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false) == nil, "distance bound")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: "falls road",
    latitude: 39.9841, longitude: -75.200, now: start.addingTimeInterval(2),
    freshNavigationStreet: true, routeTransition: false,
    differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false) == nil, "road changed")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: road,
    latitude: 39.9841, longitude: -75.200, now: start.addingTimeInterval(2),
    freshNavigationStreet: false, routeTransition: false,
    differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false) == nil, "stale CarPlay cannot hold")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: road,
    latitude: 39.9841, longitude: -75.200, now: start.addingTimeInterval(2),
    freshNavigationStreet: true, routeTransition: true,
    differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false) == nil, "maneuver transition")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: road,
    latitude: 39.9841, longitude: -75.200, now: start.addingTimeInterval(2),
    freshNavigationStreet: true, routeTransition: false,
    differentRoadGeometryNearby: true, contradictoryPostedLimitNearby: false) == nil, "other nearby road")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(anchor, roadIdentity: road,
    latitude: 39.9841, longitude: -75.200, now: start.addingTimeInterval(2),
    freshNavigationStreet: true, routeTransition: false,
    differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: true) == nil, "35mph contradicts 25")
check(CurrentNavSameRoadContinuity.bridgeUnmappedGap(nil, roadIdentity: road,
    latitude: 39.9841, longitude: -75.200, now: start.addingTimeInterval(2),
    freshNavigationStreet: true, routeTransition: false,
    differentRoadGeometryNearby: false, contradictoryPostedLimitNearby: false) == nil, "do not invent 25")
// A directly tagged new speed overrides the previous anchor.
let tagged = CurrentNavSameRoadContinuity.verified(identity: road, speedMph: 35,
    latitude: 39.99, longitude: -75.20, now: start.addingTimeInterval(20))!
check(tagged.speedMph == 35, "explicitly tagged new limit")
print("NATIVE_MLK_GEOMETRY_GAP_BRIDGE_PASS")
'''
    with tempfile.TemporaryDirectory() as td:
        main=Path(td)/'main.swift';main.write_text(code)
        executable=Path(td)/'replay'
        p=subprocess.run(['swiftc',str(POLICY),str(IDENTITY),str(MATCH),str(main),'-o',str(executable)],capture_output=True,text=True,timeout=70)
        assert p.returncode==0,p.stderr
        run=subprocess.run([str(executable)],capture_output=True,text=True,timeout=30)
        assert run.returncode==0,run.stderr
        assert 'NATIVE_MLK_GEOMETRY_GAP_BRIDGE_PASS' in run.stdout
