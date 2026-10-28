"""v24.43: native status classification + v24.41 identity anti-highway checks.
The HTTP fixture is synthetic; road-name and geometry policy are production Swift.
The live adapter can still withhold source IDR, which this does not simulate.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import pytest
ROOT = Path(__file__).resolve().parents[1]
VEH = ROOT / 'ios/HUDController/Vehicle'
ENGINE = (VEH / 'OriginalSpeedLimitEngine.swift').read_text()
VIDEO = (ROOT / 'ios/HUDController/MapMode/U2WMainVideoClient.swift').read_text()


def test_audit_is_independent_and_records_real_named_roads():
    assert 'way[maxspeed][highway](around:' in ENGINE
    assert 'auditCurrentNavNamedRoadIfNeeded(at location: CLLocation, roadName: String)' in ENGINE
    assert 'CurrentNavOSMQuery.namedRoadAudit(' in ENGINE
    query_source = (VEH / 'CurrentNavOSMQuery.swift').read_text()
    assert '[timeout:50]' in query_source
    assert '[name~' in query_source
    assert 'way[highway][ref](around:' not in ENGINE
    assert 'currentNavRoadAuditInFlight = true' in ENGINE
    assert 'currentNavRoadAuditNextAt = Date().addingTimeInterval(120)' in ENGINE
    assert 'CURRENT NAV AUDIT' in ENGINE
    assert 'recordCurrentNavArea(at: center, elements: response.elements,' in ENGINE
    assert 'mergedCurrentNavOSMElements(area.elements, mergedElements)' in ENGINE
    assert 'CurrentNavRoadAuditPolicy.classification(' in ENGINE
    assert 'no borrowed highway limit' in ENGINE
    assert 'CurrentNavRoadMatchPolicy.eligible(' in ENGINE
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in ENGINE


def test_one_shot_mid_drive_8969_preserves_carplay_and_adapter():
    assert 'midDriveRecoveryWaitSeconds: TimeInterval = 8.0' in VIDEO
    assert 'self.transportPhase == "WAITING_FRESH_IDR"' in VIDEO
    assert 'self.midDriveCodecFailureAt' in VIDEO
    assert '!self.midDriveRecoveryAttempted' in VIDEO
    assert 'self.frameCount > 100' in VIDEO
    assert 'bytesAreFresh' in VIDEO
    assert 'self.midDriveRecoveryAttempted = true' in VIDEO
    assert 'restartWorkerWithReadOnlyBootstrap(reason: "mid-drive -8969, no fresh IDR")' in VIDEO
    assert 'self.midDriveRecoveryAttempted = false' in VIDEO
    assert 'self.midDriveCodecFailureAt = nil' in VIDEO
    assert 'worker?.stop()' in VIDEO   # only iPhone's worker; U2W firmware untouched


def test_native_swift_audit_policy_and_name_geometry_safety():
    if not shutil.which('swiftc'):
        pytest.skip('swiftc unavailable')
    with tempfile.TemporaryDirectory() as folder:
        path=Path(folder)
        (path/'main.swift').write_text(r'''
import Foundation
// A failed HTTP request is NEVER evidence of a missing speed tag.
precondition(CurrentNavRoadAuditPolicy.classification(httpSucceeded:false, namedRoadCount:0, nearbyNamedRoadCount:0, explicitlyTaggedNearbyCount:0) == "REQUEST_FAILED_INDETERMINATE")
// A successful speed-tagged query returning zero cannot prove an untagged road absent.
precondition(CurrentNavRoadAuditPolicy.classification(httpSucceeded:true, namedRoadCount:0, nearbyNamedRoadCount:0, explicitlyTaggedNearbyCount:0) == "ROAD_NAME_NOT_RETURNED_IN_LOCAL_QUERY")
precondition(CurrentNavRoadAuditPolicy.classification(httpSucceeded:true, namedRoadCount:2, nearbyNamedRoadCount:0, explicitlyTaggedNearbyCount:0) == "ROAD_NAME_PRESENT_BUT_GEOMETRY_OUTSIDE_CORRIDOR")
precondition(CurrentNavRoadAuditPolicy.classification(httpSucceeded:true, namedRoadCount:2, nearbyNamedRoadCount:1, explicitlyTaggedNearbyCount:0) == "NEARBY_NAMED_WAY_NO_SUPPORTED_SPEED_TAG")
precondition(CurrentNavRoadAuditPolicy.classification(httpSucceeded:true, namedRoadCount:2, nearbyNamedRoadCount:1, explicitlyTaggedNearbyCount:1) == "NEARBY_NAMED_WAY_HAS_EXPLICIT_SPEED_TAG")
// A close expressway must not become the selected limit for the named local road.
precondition(!CurrentNavRoadIdentity.routeRoadMatches("Martin Luther King Jr Dr", name:"Schuylkill Expressway", reference:nil))
precondition(CurrentNavRoadIdentity.routeRoadMatches("Martin Luther King Jr Dr", name:"Martin Luther King Junior Drive", reference:nil))
precondition(!CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch:false, distanceMeters:2, gpsAccuracyMeters:5, moving:true, headingErrorDegrees:0))
precondition(CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch:true, distanceMeters:4, gpsAccuracyMeters:5, moving:true, headingErrorDegrees:3))
print("audit response classification and street-identity safety PASS")
''')
        exe=path/'check'
        c=subprocess.run(['swiftc', str(VEH/'CurrentNavRoadAuditPolicy.swift'), str(VEH/'CurrentNavRoadIdentity.swift'), str(VEH/'CurrentNavRoadMatchPolicy.swift'), str(path/'main.swift'), '-o', str(exe)],capture_output=True,text=True,timeout=45)
        assert c.returncode==0,c.stderr
        x=subprocess.run([str(exe)],capture_output=True,text=True,timeout=5)
        assert x.returncode==0,x.stderr+x.stdout
        assert 'PASS' in x.stdout
