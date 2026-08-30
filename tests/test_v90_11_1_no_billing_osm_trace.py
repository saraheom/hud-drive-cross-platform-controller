from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEED = (ROOT / "ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift").read_text()
VEHICLE = (ROOT / "ios/HUDController/UI/VehicleView.swift").read_text()
README = (ROOT / "README.md").read_text()


def test_here_removed_from_runtime_and_ui():
    assert 'case here = "HERE"' not in SPEED
    assert "routematching.hereapi.com" not in SPEED
    assert "HereAPIKeyStore" not in SPEED
    assert "Save HERE Key" not in VEHICLE
    assert "Clear HERE" not in VEHICLE


def test_three_no_billing_sources_are_exposed():
    assert 'case current = "Current"' in SPEED
    assert 'case traceOSM = "OSM Trace"' in SPEED
    assert 'case improvedTracePhilly = "Improved + Philly GIS"' in SPEED
    assert 'case enhancedOSM = "Enhanced OSM"' not in SPEED
    assert "No HERE code, API key, or commercial map-service dependency remains" in README


def test_trace_matcher_uses_recent_history_and_confidence_before_switching():
    assert "traceLocations" in SPEED
    assert "Array(traceLocations.suffix(8))" in SPEED
    assert "traceCurrentSegmentID" in SPEED
    assert "margin >= 0.30" in SPEED
    assert "if next >= 2" in SPEED
    assert "The newest point must still be plausibly on this road" in SPEED


def test_osm_directional_and_conditional_tags_are_requested():
    assert 'maxspeedForward = "maxspeed:forward"' in SPEED
    assert 'maxspeedBackward = "maxspeed:backward"' in SPEED
    assert 'maxspeedConditional = "maxspeed:conditional"' in SPEED
    assert 'maxspeedForwardConditional = "maxspeed:forward:conditional"' in SPEED
    assert 'maxspeedBackwardConditional = "maxspeed:backward:conditional"' in SPEED
    assert "parseSimpleConditionalMaxSpeed" in SPEED
    assert '"wet", "snow", "ice", "flashing"' in SPEED
