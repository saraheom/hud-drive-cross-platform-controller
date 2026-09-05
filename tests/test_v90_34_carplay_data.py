from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text()


def test_now_playing_comes_from_u2w_and_spotify_runtime_dependency_is_removed():
    media = read("ios/HUDController/Media/CarPlayNowPlayingClient.swift")
    app = read("ios/HUDController/App/AppState.swift")
    ui = read("ios/HUDController/UI/MediaView.swift")
    project = read("ios/project.yml")
    assert "u2wmedia-live.cgi" in media
    assert "u2wmedia-artwork.cgi" in media
    assert "let nowPlaying: CarPlayNowPlayingClient" in app
    assert "pushNowPlayingMetadataToHUD" in app
    assert "CarPlay Now Playing" in ui
    assert "Authorize Spotify" not in ui
    assert "package: SpotifyiOS" not in project
    # Historical source is retained for archaeology but explicitly excluded.
    assert "Media/SpotifyMediaController.swift" in project


def test_route_liveness_uses_successful_endpoint_refresh_not_sequence_progress():
    route = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "endpointStaleInterval: TimeInterval = 4.5" in route
    assert "TimedSnapshot(snapshot: snapshot, receivedAt: now)" in route
    assert "An unchanged sequence simply means the route state did not change" in route
    assert "lastSequenceProgressAtBySource" in route  # diagnostics/reroute only
    assert "freshnessInterval(for snapshot" not in route


def test_route_corridor_speed_lookup_is_connected_unanimous_and_nonwarning():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "scheduleRouteCorridorLookup" in speed
    assert "corridorWaysConnected" in speed
    assert "observations.count >= 2" in speed
    assert "speeds.count == 1" in speed
    assert "OSM Route Guidance corridor consensus" in speed
    assert "warningEligible: false" in speed
    assert "min(3_000, context.distanceToManeuverMeters + 600)" in speed


def test_waze_priority_remains_but_no_speculative_client_side_force_enable():
    route = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert 'case waze = "Waze"' in route
    assert 'case .waze: 100' in route
    assert "sourceSupportsRouteGuidance" not in route
