"""v24.44: compile and execute actual Swift query/cache/HTTP diagnostic policies.
The HTTP fixtures are synthetic: we do not claim a live Overpass server response.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import pytest
ROOT=Path(__file__).resolve().parents[1]
V=ROOT/'ios/HUDController/Vehicle'
ENGINE=(V/'OriginalSpeedLimitEngine.swift').read_text()
LOG=(Path('/mnt/data/HUD_2026-10-27_23-43-24.log'))


def test_production_audit_uses_targeted_query_and_preserves_original_current():
    assert 'CurrentNavOSMQuery.namedRoadAudit(' in ENGINE
    assert 'CurrentNavOSMTransport.errorSummary(data: data)' in ENGINE
    assert 'AUDIT_REQUEST_FAILED_INDETERMINATE' not in ENGINE or 'AUDIT_\\(classification)' in ENGINE
    assert 'recordCurrentNavArea(at: center, elements: response.elements,' in ENGINE
    assert 'radiusMeters: Double(currentNavRoadAuditRadiusMeters)' in ENGINE
    assert 'radiusMeters: Double(currentNavPrimaryQueryRadiusMeters)' in ENGINE
    assert 'CurrentNavCacheCoverage.contains(' in ENGINE
    assert 'currentNavOverpassEndpointIndex = (currentNavOverpassEndpointIndex + 1)' in ENGINE
    assert 'let query = "[out:json];way[maxspeed][highway](around:400,' in ENGINE
    assert 'let (data, response) = try await URLSession.shared.data(from: url)' in ENGINE
    assert 'if let remark = result.remark, !remark.isEmpty' in ENGINE


def test_real_october_28_log_contains_failed_audits_not_missing_speed_evidence():
    if not LOG.exists(): pytest.skip('prior drive log not mounted')
    t=LOG.read_text(errors='replace')
    assert 'AUDIT_REQUEST_FAILED_INDETERMINATE' in t
    assert 'purpose=named-road-identity-audit' in t
    assert 'HTTP=400' in t
    assert 'NEARBY_NAMED_WAY_NO_SUPPORTED_SPEED_TAG' not in t


def test_native_swift_road_query_and_cache_footprint_and_http_summary():
    if not shutil.which('swiftc'): pytest.skip('swiftc unavailable')
    code=r'''
import Foundation

let cases: [(String,String)] = [
    ("N 34th St", "34th"), ("Powelton Ave","powelton"),
    ("Martin Luther King Jr Dr", "luther"), ("MLK Dr", "luther"),
    ("River Ridge Ct", "ridge")
]
for (name, token) in cases {
    precondition(CurrentNavOSMQuery.auditSearchToken(name) == token, name)
    guard let query = CurrentNavOSMQuery.namedRoadAudit(roadName:name,
               latitude:39.96412, longitude:-75.19201, radiusMeters:170) else { fatalError(name) }
    precondition(query.contains("[name~\"" + token + "\",i]"))
    precondition(query.contains("[timeout:50]"))
    precondition(!query.contains("[ref]"))
}
precondition(CurrentNavOSMQuery.namedRoadAudit(roadName:"US 1",latitude:39.9,longitude:-75.2,radiusMeters:170) == nil)
precondition(CurrentNavCacheCoverage.contains(queryRadiusMeters:400,distanceMeters:375))
precondition(!CurrentNavCacheCoverage.contains(queryRadiusMeters:170,distanceMeters:200))
precondition(CurrentNavCacheCoverage.contains(queryRadiusMeters:170,distanceMeters:150))
precondition(CurrentNavCacheCoverage.contains(queryRadiusMeters:nil,distanceMeters:375))
precondition(CurrentNavCacheCoverage.mergedRadius(incomingRadiusMeters:170,priorRadii:[400]) == 400)
let html = Data("<html><body>runtime error: Query timed out</body></html>".utf8)
precondition(CurrentNavOSMTransport.errorSummary(data:html) == "runtime error: Query timed out")
precondition(!CurrentNavRoadIdentity.routeRoadMatches("MLK Dr",name:"Schuylkill Expressway",reference:nil))
precondition(CurrentNavRoadIdentity.routeRoadMatches("MLK Dr",name:"Martin Luther King Junior Drive",reference:nil))
print("v24.44 native audit/caching/replay PASS")
'''
    with tempfile.TemporaryDirectory() as d:
        m=Path(d)/'main.swift'; m.write_text(code)
        exe=Path(d)/'run'
        r=subprocess.run(['swiftc',*[str(V/x) for x in ['CurrentNavOSMQuery.swift','CurrentNavRoadIdentity.swift','CurrentNavCacheCoverage.swift','CurrentNavOSMTransport.swift']],str(m),'-o',str(exe)],capture_output=True,text=True,timeout=60)
        assert r.returncode == 0, r.stderr
        p=subprocess.run([str(exe)],capture_output=True,text=True,timeout=8)
        assert p.returncode == 0,p.stderr+p.stdout
        assert 'PASS' in p.stdout
