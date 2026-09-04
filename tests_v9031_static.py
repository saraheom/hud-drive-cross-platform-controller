from pathlib import Path
ROOT = Path(__file__).resolve().parent

def read(rel): return (ROOT/rel).read_text()

def test_adapter_only_no_ocr_fallback():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    nav = read("ios/HUDController/Navigation/HudNavigationController.swift")
    app = read("ios/HUDController/App/AppState.swift")
    card = read("ios/HUDController/UI/RouteGuidanceStatusCard.swift")
    assert "HUD returned to Freeride" in rg
    assert "if owner == .ocr { return false }" in nav
    assert "presentFullDisplayPicker()" not in app.split("func quickStartNavigation()",1)[1].split("func quickReconnectSpotify",1)[0]
    assert "capture.requestAutomaticStartIfDesired()" not in app
    assert "capture.hudSessionDidReset" not in app
    root = read("ios/HUDController/UI/RootView.swift")
    assert "capture.appBecameActive()" not in root
    assert "There is no OCR fallback" in card

def test_route_guidance_priority_and_endpoint():
    rg = read("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert 'u2wrgd-live.cgi' in rg
    assert 'case googleMaps = "Google Maps"' in rg
    assert 'case appleMaps = "Apple Maps"' in rg
    assert 'case waze = "Waze"' in rg
    assert 'case .googleMaps: 300' in rg
    assert 'case .appleMaps: 200' in rg
    assert 'case .waze: 100' in rg
    assert 'guard kind != .other' in rg

def test_eta_native_packet_and_dashboard_defaults():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    obd = read("ios/HUDController/Vehicle/HudOBDController.swift")
    assert 'p1: 114' in commands and 'HudProtocol.int64(arrivalTimeMilliseconds)' in commands
    assert 'fallback: .speed' in obd
    assert 'fallback: .eta' in obd
    assert 'v9031NavigationETAMigrated' in obd
    assert 'legacyDefaultPair' in obd

def test_no_screen_capture_background_dependency():
    project = read("ios/project.yml")
    modes = project.split("UIBackgroundModes:",1)[1].split("UIFileSharingEnabled",1)[0]
    assert "bluetooth-central" in modes and "location" in modes
    assert "screen-capture" not in modes


def test_locked_drive_background_execution_support():
    speed = read("ios/HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
    assert "allowsBackgroundLocationUpdates = true" in speed
    assert "pausesLocationUpdatesAutomatically = false" in speed
