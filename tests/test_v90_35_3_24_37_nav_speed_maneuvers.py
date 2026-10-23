"""Release v24.37 source checks; no physical HUD is available in CI."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ios/HUDController"


def test_only_two_speed_limit_options_are_exposed():
    engine = (SRC / "Vehicle/OriginalSpeedLimitEngine.swift").read_text()
    ui = (SRC / "UI/VehicleView.swift").read_text()
    assert 'case currentNav = "Current + Nav"' in engine
    assert 'static var allCases: [SpeedLimitSourceMode] { [.current, .currentNav] }' in engine
    assert 'ForEach(SpeedLimitSourceMode.allCases)' in ui
    assert 'Text(source.rawValue).tag(source)' in ui
    assert 'if storedSource == SpeedLimitSourceMode.currentNav.rawValue' in engine
    assert 'self.sourceMode = .current' in engine


def test_baseline_current_remains_original_method():
    engine = (SRC / "Vehicle/OriginalSpeedLimitEngine.swift").read_text()
    assert 'case .current:\n            limit = bestSpeedLimit(at: location)' in engine
    assert 'case .currentNav:\n            limit = bestCurrentNavSpeedLimit(at: location)' in engine
    assert 'case .current:\n            await updateOriginalSegmentsIfNeeded' in engine
    assert 'case .currentNav:\n            await updateCurrentNavRoadsIfNeeded' in engine
    assert 'way[maxspeed][highway](around:400' in engine
    assert 'Self.originalPolygonContains(' in engine
    assert 'Self.routeRoadMatches(navRoad, name: candidate.name, reference: candidate.reference)' in engine
    assert 'CurrentNavRoadMatchPolicy.eligible(' in engine
    assert 'currentNavDisplayHold = true' in engine
    assert 'sourceMode == .currentNav ? currentNavMatchFresh : true' in engine
    assert 'currentNavHoldMaxSeconds: TimeInterval = 12.0' in engine


def test_uturn_uses_uploaded_reference_not_symbol_rotation():
    ui = (SRC / "MapMode/HudMapModeCanvas.swift").read_text()
    assert 'snapshot.maneuver == .uTurn' in ui
    assert 'Image(approvedUTurnAssetName)' in ui
    assert 'Image(systemName: "arrow.uturn.left")' not in ui
    original = ROOT / 'docs/assets/approved_uturn_2026_10_22.svg'
    assert original.exists() and 'rotate(-90 33.118 37.974)' in original.read_text()
    for weight in ('Thin', 'Regular', 'Bold'):
        folder = SRC / f'Assets.xcassets/MapModeApprovedUTurn{weight}.imageset'
        metadata = json.loads((folder / 'Contents.json').read_text())
        image = folder / metadata['images'][0]['filename']
        assert image.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
    assert 'settings.maneuverArrowThickness' in ui


def test_roundabout_exit_number_is_carried_to_actual_map_renderer():
    snapshot = (SRC / "MapMode/HudMapModeSnapshot.swift").read_text()
    state = (SRC / "App/AppState.swift").read_text()
    ui = (SRC / "MapMode/HudMapModeCanvas.swift").read_text()
    guidance = (SRC / "Navigation/RouteGuidanceAdapterClient.swift").read_text()
    assert 'var exitNumber: Int? = nil' in snapshot
    assert 'exitNumber: navigation.current.exitNumber' in state
    assert 'exitNumber: Self.roundaboutExit(for: maneuver.type)' in guidance
    assert 'snapshot.maneuver == .roundabout' in ui
    assert 'let exitNumber = snapshot.exitNumber, exitNumber > 0' in ui
    assert 'Text(String(exitNumber))' in ui
    assert 'RoundaboutHighlightedExit' in ui
    assert 'Image(systemName: snapshot.maneuver.symbol)' in ui  # Unknown ordinal fallback
    assert 'Text("EXIT")' not in ui


def test_no_mainvideo_or_firmware_modifications_needed():
    ui = (SRC / "MapMode/HudMapModeCanvas.swift").read_text()
    assert 'VideoToolbox' not in ui
    assert 'tcp/15332' not in ui
