"""v24.38 validation against Oct 22 Sweetbriar/MLK 50-mph failure.

Uses the actual new Swift production geometry policy where possible. The
Python source-contract checks do not pretend to be full iOS SDK type checks.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ios/HUDController"
ENGINE = (SRC / "Vehicle/OriginalSpeedLimitEngine.swift").read_text()
STATE = (SRC / "App/AppState.swift").read_text()
OBD = (SRC / "Vehicle/HudOBDController.swift").read_text()
POLICY = SRC / "Vehicle/CurrentNavRoadMatchPolicy.swift"


def test_true_identity_gate_rejects_expressway_even_when_nearby():
    """Execute the Swift gate itself with a highway closer than MLK."""
    if not shutil.which("swiftc"):
        import pytest
        pytest.skip("Swift compiler not available")
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        (d / "main.swift").write_text('''
import Foundation
let lat = 39.987, lon = -75.194
let horizontalEnd = 0.002
// MLK centerline 8m away; expressway centerline just 2m away.
let mlkDistance = CurrentNavRoadMatchPolicy.distanceToSegmentMeters(
 latitude: lat, longitude: lon,
 startLatitude: lat + 8.0/111132.0, startLongitude: lon - horizontalEnd,
 endLatitude: lat + 8.0/111132.0, endLongitude: lon + horizontalEnd)
let interstateDistance = CurrentNavRoadMatchPolicy.distanceToSegmentMeters(
 latitude: lat, longitude: lon,
 startLatitude: lat + 2.0/111132.0, startLongitude: lon - horizontalEnd,
 endLatitude: lat + 2.0/111132.0, endLongitude: lon + horizontalEnd)
precondition(mlkDistance > interstateDistance)
precondition(CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch: true, distanceMeters: mlkDistance, gpsAccuracyMeters: 8,
 moving: true, headingErrorDegrees: 5))
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch: false, distanceMeters: interstateDistance, gpsAccuracyMeters: 8,
 moving: true, headingErrorDegrees: 5))
// A large road segment 85m away used to pass the legacy endpoint-circle gate.
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch: true, distanceMeters: 85, gpsAccuracyMeters: 10,
 moving: true, headingErrorDegrees: 5))
// An orthogonal frontage road cannot win just from a matching name.
precondition(!CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch: true, distanceMeters: 5, gpsAccuracyMeters: 8,
 moving: true, headingErrorDegrees: 88))
// A stationary fix has unreliable heading but must still be on the named way.
precondition(CurrentNavRoadMatchPolicy.eligible(
 semanticRoadNameMatch: true, distanceMeters: 10, gpsAccuracyMeters: 8,
 moving: false, headingErrorDegrees: 130))
print("Swift road identity + geometric gating tests PASSED")
''')
        binary = d / "policy_checks"
        p = subprocess.run(["swiftc", str(POLICY), str(d / "main.swift"), "-o", str(binary)],
                           capture_output=True, text=True, timeout=45)
        assert p.returncode == 0, p.stderr
        r = subprocess.run([str(binary)], capture_output=True, text=True, timeout=5)
        assert r.returncode == 0, r.stderr
        assert "PASSED" in r.stdout


def test_current_is_verbatim_original_algorithm_with_independent_nav_query():
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded' in ENGINE
    assert 'way[maxspeed][highway](around:400' in ENGINE
    assert 'Self.originalPolygonContains(' in ENGINE
    assert 'case .currentNav:\n            await updateCurrentNavRoadsIfNeeded' in ENGINE
    assert 'way[highway~' in ENGINE
    assert 'currentNavRoads = combined.compactMap(Self.makeCurrentNavRoad)' in ENGINE
    assert 'let posted = tags.maxspeed.flatMap' in ENGINE


def test_nav_street_identity_is_required_before_applying_speed():
    assert 'let semanticMatch = Self.routeRoadMatches(navRoad, name: candidate.name, reference: candidate.reference)' in ENGINE
    assert 'CurrentNavRoadMatchPolicy.eligible(' in ENGINE
    assert 'guard let winner = scored.first else {' in ENGINE
    assert 'let directMph = chosen.speedKmh.map' in ENGINE
    assert 'connectedCurrentNavLimit(for: chosen, road: navRoad, location: location)' in ENGINE
    assert 'guard let mph = directMph ?? conflictSafeConnectedMph, mph > 0 else {' in ENGINE
    assert 'currentNavMatchFresh = currentNavQueryAt.map {' in ENGINE
    assert 'currentNavDisplayHold = true // connected-road value is display only' in ENGINE
    assert 'no borrowed highway limit' in ENGINE


def test_road_change_and_untagged_road_fail_closed():
    assert 'currentNavObservedStreet != identity' in ENGINE
    assert 'clearDisplayedLimit(reason: "CarPlay street changed to' in ENGINE
    assert 'clearDisplayedLimit(reason: "Current + Nav has no verified posted speed:' in ENGINE
    assert 'return heldCurrentNavSpeed(road: identity, location: location)' in ENGINE
    assert 'Set<Int> = []' in ENGINE
    assert 'posted.count == 1' in ENGINE
    assert 'Self.endpointDistance(node, candidate) <= 20' in ENGINE
    assert 'SPEED CURRENT NAV QUERY' in ENGINE


def test_ble_disconnected_cancels_elm_recovery_without_issuing_offline_hud_commands():
    assert 'self.directELM.releaseMapModeOwnership()' in STATE
    assert 'self.obd.clearDirectELMOwnershipSuspensionAfterHUDDisconnect(' in STATE
    assert 'func clearDirectELMOwnershipSuspensionAfterHUDDisconnect' in OBD
    assert 'directELMOwnershipSuspended = false' in OBD
    assert 'self.mapModeDirectOBDOwnershipTask?.cancel()' in STATE


def test_historical_failure_is_a_real_regression_case():
    log = Path('/mnt/data/HUD_2026-10-22_12-55-02.log')
    if not log.is_file():
        import pytest
        pytest.skip('prior test drive log not mounted')
    txt = log.read_text(errors='replace')
    lines = [line for line in txt.splitlines() if 'SPEED CURREN' in line]
    # Captures the real failure v24.37 allowed before strict name verification.
    assert any('Schuylkill Expressway' in line and 'Martin Luther King Jr Dr' in line and 'nameBonus=0' in line for line in lines)
    assert any('Schuylkill Expressway' in line and 'Sweetbriar Dr' in line for line in lines)
