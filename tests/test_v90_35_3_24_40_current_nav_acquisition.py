"""v24.40 acquisition regression: proven Current request, optional enrichment,
cellular-only TLS fallback for local-only CarPlay Wi-Fi, and roundabout sizing.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'ios/HUDController'
ENGINE = (SRC / 'Vehicle/OriginalSpeedLimitEngine.swift').read_text()
CANVAS = (SRC / 'MapMode/HudMapModeCanvas.swift').read_text()
CELLULAR = (SRC / 'Vehicle/CurrentNavCellularHTTPS.swift').read_text()
PARSER = SRC / 'Vehicle/CurrentNavHTTPResponseParser.swift'


def test_main_current_nav_query_is_the_original_small_speed_tagged_query():
    assert 'let primaryQuery = "[out:json];way[maxspeed][highway](around:' in ENGINE
    assert 'currentNavPrimaryQueryRadiusMeters = 400' in ENGINE
    assert 'fetchCurrentNavOSM(query: primaryQuery' in ENGINE
    assert 'currentNavNetworkVerifiedWayIDs.formUnion(tagged.map(\.id))' in ENGINE
    assert 'recordCurrentNavArea(at: target, elements: primary.elements)' in ENGINE
    # The original Current path stays independently available.
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded(at: location, force: force)' in ENGINE


def test_untagged_road_query_is_optional_and_cannot_erase_valid_data():
    assert 'let supplemental = "[out:json][timeout:12];way[highway][name](around:' in ENGINE
    assert 'currentNavSupplementaryQueryRadiusMeters = 160' in ENGINE
    assert 'SUPPLEMENTARY FAILED' in ENGINE
    assert 'primary speed-tagged cache retained' in ENGINE
    assert 'recordCurrentNavArea(at: live, elements: extra.elements)' in ENGINE
    assert 'guard let context = freshCarPlayRouteContext()' in ENGINE


def test_offline_carplay_wifi_does_not_force_unsafe_geometry_fallback():
    assert 'CurrentNavOSMTransport.download(url: url)' in ENGINE
    assert 'session.data(from: url)' in (SRC / 'Vehicle/CurrentNavOSMTransport.swift').read_text()
    assert 'request.timeoutInterval = 11' not in ENGINE
    assert 'CurrentNavCellularHTTPS.fetch(url: url, timeout: 12)' in ENGINE
    assert 'NSURLErrorNotConnectedToInternet' in ENGINE
    assert 'NSURLErrorTimedOut' in ENGINE
    assert 'parameters.requiredInterfaceType = .cellular' in CELLULAR
    assert 'NWParameters(tls: NWProtocolTLS.Options()' in CELLULAR
    assert 'no borrowed highway limit' in ENGINE
    assert 'let semanticMatch = Self.routeRoadMatches(navRoad, name: candidate.name, reference: candidate.reference)' in ENGINE
    assert 'currentNavNetworkVerifiedWayIDs.contains(chosen.id)' in ENGINE


def test_roundabout_has_normal_size_and_legible_single_number():
    assert 'RoundaboutRouteGlyph(exitNumber: exitNumber)\n                    .frame(width: 39, height: 39)' in CANVAS
    assert 'size: exitNumber < 10 ? 16 : 13' in CANVAS
    assert 'Text(String(exitNumber))' in CANVAS
    assert 'MapModeApprovedUTurnRegular' in CANVAS


def test_cellular_http_parser_accepts_only_complete_successful_http():
    if not shutil.which('swiftc'):
        import pytest
        pytest.skip('swiftc unavailable')
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        (folder / 'main.swift').write_text(r'''
import Foundation
let normal = Data("HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\n{\"x\":1}".utf8)
let normalResult = try CurrentNavHTTPResponseParser.body(from: normal)
precondition(String(decoding: normalResult, as: UTF8.self) == "{\"x\":1}")
let chunked = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7\r\n{\"x\":1}\r\n0\r\n\r\n".utf8)
let chunkedResult = try CurrentNavHTTPResponseParser.body(from: chunked)
precondition(String(decoding: chunkedResult, as: UTF8.self) == "{\"x\":1}")
let failed = Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 3\r\n\r\nerr".utf8)
do {
  _ = try CurrentNavHTTPResponseParser.body(from: failed)
  fatalError("HTTP 502 must not supply road-data bytes")
} catch { }
let incomplete = Data("HTTP/1.1 200 OK\r\nContent-Length: 20\r\n\r\n{}".utf8)
do {
  _ = try CurrentNavHTTPResponseParser.body(from: incomplete)
  fatalError("truncated response must not be accepted")
} catch { }
print("CurrentNav response parser PASS")
''')
        target = folder / 'check'
        build = subprocess.run(['swiftc', str(PARSER), str(folder / 'main.swift'), '-o', str(target)],
                               capture_output=True, text=True, timeout=45)
        assert build.returncode == 0, build.stderr
        run = subprocess.run([str(target)], capture_output=True, text=True, timeout=5)
        assert run.returncode == 0, run.stderr
        assert 'PASS' in run.stdout
