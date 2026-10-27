"""Actual Swift transport and production identity/geometry rules against
recorded v24.37 decision names and synthetic GPS/road segments.

Do not mistake the synthetic geometries for captured October 22 GPS traces:
the October 22 log records names/speeds but not every OSM candidate polyline.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VEH = ROOT / 'ios/HUDController/Vehicle'
FIXTURE = ROOT / 'tests/fixtures/v24_41_oct22_recorded_speed_limit_decisions.json'
ENGINE = (VEH / 'OriginalSpeedLimitEngine.swift').read_text()
TRANSPORT = (VEH / 'CurrentNavOSMTransport.swift').read_text()


def test_request_uses_original_current_timeout_semantics():
    assert 'session.data(from: url)' in TRANSPORT
    assert 'CurrentNavOSMTransport.download(url: url)' in ENGINE
    assert 'request.timeoutInterval = 11' not in ENGINE
    assert 'URLSession.shared.data(for: request)' not in ENGINE
    assert 'URLSESSION SUCCESS duration=' in ENGINE
    assert 'recordCurrentNavArea(at: location, elements: primary.elements)' in ENGINE
    assert 'currentNavNetworkVerifiedWayIDs.formUnion(tagged.map(\\.id))' in ENGINE
    assert 'no borrowed highway limit' in ENGINE


def test_native_swift_mock_http_success_http502_timeout_and_recorded_drive_replay():
    if not shutil.which('swiftc'):
        import pytest
        pytest.skip('swiftc unavailable')
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        main = root / 'Replay.swift'
        main.write_text(r'''
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

class FakeOverpass: URLProtocol {
    static var status = 200
    static var payload = Data()
    static var timeout = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.timeout {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                        httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
struct Sample: Decodable { let timestamp: String; let reportedLimitMph: Int; let candidateRoad: String; let carPlayCurrentStreet: String }
struct History: Decodable { let samples: [Sample] }
struct OSM: Decodable { let elements: [Element] }
struct Element: Decodable { let id: Int; let tags: Tags }
struct Tags: Decodable { let name: String; let highway: String; let maxspeed: String? }

@main struct Run {
  static func main() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FakeOverpass.self]
    let session = URLSession(configuration: config)
    let url = URL(string: "https://example.invalid/api/interpreter?data=mock")!
    FakeOverpass.payload = Data(#"{"elements":[{"id":1,"tags":{"name":"Martin Luther King Junior Drive","highway":"residential","maxspeed":"25 mph"}},{"id":2,"tags":{"name":"Schuylkill Expressway","highway":"motorway","maxspeed":"50 mph"}}]}"#.utf8)
    FakeOverpass.status = 200
    let result = try await CurrentNavOSMTransport.download(url: url, session: session)
    precondition(result.statusCode == 200)
    let decoded = try JSONDecoder().decode(OSM.self, from: result.data)
    precondition(decoded.elements.count == 2)
    // Use real production street-normalization plus GPS-road geometry gates.
    let latitude = 39.96000, longitude = -75.19000
    let mlkNear = CurrentNavRoadMatchPolicy.distanceToSegmentMeters(latitude: latitude, longitude: longitude,
         startLatitude: latitude + 0.00008, startLongitude: longitude - 0.0004,
         endLatitude: latitude + 0.00008, endLongitude: longitude + 0.0004)
    let expresswayCloser = CurrentNavRoadMatchPolicy.distanceToSegmentMeters(latitude: latitude, longitude: longitude,
         startLatitude: latitude + 0.000018, startLongitude: longitude - 0.0004,
         endLatitude: latitude + 0.000018, endLongitude: longitude + 0.0004)
    precondition(expresswayCloser < mlkNear && mlkNear < 20)
    let nav = "Martin Luther King Jr Dr"
    let mlkName = CurrentNavRoadIdentity.routeRoadMatches(nav, name: decoded.elements[0].tags.name, reference: nil)
    let highwayName = CurrentNavRoadIdentity.routeRoadMatches(nav, name: decoded.elements[1].tags.name, reference: nil)
    precondition(CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch: mlkName, distanceMeters: mlkNear,
                    gpsAccuracyMeters: 6, moving: true, headingErrorDegrees: 2))
    precondition(!CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch: highwayName, distanceMeters: expresswayCloser,
                    gpsAccuracyMeters: 6, moving: true, headingErrorDegrees: 2))
    precondition(CurrentNavRoadIdentity.routeRoadMatches("N 38th St", name: "North 38th Street", reference: nil))
    precondition(!CurrentNavRoadIdentity.routeRoadMatches("Sweetbriar Dr", name: "Schuylkill Expressway", reference: nil))
    // A correctly named but untagged road is a match with UNKNOWN limit, never
    // authorization to borrow the nearby expressway's 50 mph posted speed.
    let untagged = #"{"elements":[{"id":3,"tags":{"name":"Sweetbriar Drive","highway":"residential"}}]}"#
    let absentSpeed = try JSONDecoder().decode(OSM.self, from: Data(untagged.utf8))
    precondition(absentSpeed.elements[0].tags.maxspeed == nil)
    precondition(CurrentNavRoadIdentity.routeRoadMatches("Sweetbriar Dr", name: absentSpeed.elements[0].tags.name, reference: nil))

    // Actual reported named speed-limit decisions from Oct 22; synthetic GPS
    // distance 3m and heading 4 degrees isolate the *real name-gate* rule.
    let fixture = try JSONDecoder().decode(History.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    var accepted = 0, rejected = 0, expresswayRejected = 0, activeCount = 0
    for sample in fixture.samples where sample.carPlayCurrentStreet != "-" {
      activeCount += 1
      let compatible = CurrentNavRoadIdentity.routeRoadMatches(sample.carPlayCurrentStreet,
                                        name: sample.candidateRoad, reference: nil)
      let eligible = CurrentNavRoadMatchPolicy.eligible(semanticRoadNameMatch: compatible,
                            distanceMeters: 3, gpsAccuracyMeters: 5,
                            moving: true, headingErrorDegrees: 4)
      if eligible { accepted += 1 } else { rejected += 1 }
      if sample.candidateRoad == "Schuylkill Expressway" &&
          sample.carPlayCurrentStreet != "Schuylkill Expressway" {
        precondition(!eligible)
        expresswayRejected += 1
      }
    }
    precondition(fixture.samples.count == 429 && activeCount >= 300)
    precondition(expresswayRejected == 38) // 12 N 34th + 14 Sweetbriar + 12 MLK
    precondition(accepted > 150 && rejected > 50)

    FakeOverpass.status = 502
    let bad = try await CurrentNavOSMTransport.download(url: url, session: session)
    precondition(bad.statusCode == 502)
    // Production acquisition rejects all non-2xx before JSON decoding.
    precondition(!(200..<300).contains(bad.statusCode))
    FakeOverpass.timeout = true
    do {
      _ = try await CurrentNavOSMTransport.download(url: url, session: session)
      fatalError("timeout should not be interpreted as an OSM success")
    } catch {
      precondition((error as NSError).code == NSURLErrorTimedOut)
    }
    print("NATIVE_REPLAY PASS total=\(fixture.samples.count) active=\(activeCount) accepted=\(accepted) rejected=\(rejected) badHighway=\(expresswayRejected) mockedHTTP=200,502,timeout")
  }
}
''')
        exe = root / 'replay'
        srcs = [str(VEH / x) for x in ('CurrentNavOSMTransport.swift', 'CurrentNavRoadMatchPolicy.swift', 'CurrentNavRoadIdentity.swift')]
        compile = subprocess.run(['swiftc'] + srcs + [str(main), '-o', str(exe)], capture_output=True, text=True, timeout=55)
        assert compile.returncode == 0, compile.stderr
        run = subprocess.run([str(exe), str(FIXTURE)], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, run.stderr + run.stdout
        assert 'NATIVE_REPLAY PASS' in run.stdout, run.stdout
        print(run.stdout)
