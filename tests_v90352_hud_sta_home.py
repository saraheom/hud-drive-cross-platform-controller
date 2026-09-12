from pathlib import Path

ROOT = Path(__file__).resolve().parent

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

def test_stock_sta_packets_and_mode6_are_implemented():
    commands = read("ios/HUDController/Protocol/HudCommands.swift")
    assert "6 = IOS_KIVICCAST_STA_MODE" in commands
    assert "static func wifiSTAMode" in commands
    assert "p1: 16, p2: 0" in commands
    assert "javaWriteUTF(ssid)" in commands
    assert "javaWriteUTF(password)" in commands
    assert "static func wifiSTAStatusRequest" in commands
    assert "p1: 17, p2: 0" in commands

def test_wifi_sta_status_event_is_parsed_and_exposed():
    bt = read("ios/HUDController/Bluetooth/HudBluetoothManager.swift")
    assert "onWiFiSTAStatusEvent" in bt
    assert "body[0] == 3, body[1] == 6, body[2] == 0" in bt
    assert 'logger.log("HUD WIFI STA"' in bt

def test_home_probe_starts_u2w_server_then_joins_mode6_without_mode5_handoff():
    app = read("ios/HUDController/App/AppState.swift")
    assert "func startHUDU2WSTAHomeProbe" in app
    assert "http://192.168.50.2/cgi-bin/u2whud-start.cgi" in app
    assert "HudCommands.kivicMode(6)" in app
    assert "HudCommands.wifiSTAMode" in app
    assert "func requestHUDU2WSTAStatus" in app
    assert "func stopHUDU2WSTAHomeProbe" in app

def test_navigation_test_ui_uses_global_green_accent():
    nav = read("ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift")
    mapui = read("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
    assert ".tint(HudTheme.accent)" in nav
    assert "private let accent = HudTheme.accent" in mapui
    assert "Color(red: 0.20, green: 0.64, blue: 1.00)" not in nav

def test_temporary_speed_marker_probe_block_is_not_in_vehicle_ui():
    vehicle = read("ios/HUDController/UI/VehicleView.swift")
    assert "SPEED MARKER PROBE — TEMPORARY" not in vehicle
    assert "speedMarkerProbeLimitMph" not in vehicle
    assert "D0 — Gauge ON" not in vehicle

def test_home_diagnostic_ui_has_credentials_status_and_no_wifi_handoff_instruction():
    ui = read("ios/HUDController/UI/NavigationHUDPreviewCard.swift")
    assert "HUD → U2W Wi-Fi home diagnostic" in ui
    assert "Start home bridge test" in ui
    assert "Request status" in ui
    assert "HUD STA IP" in ui
    assert "Do not manually join HUDWAY Drive Wi-Fi" in ui
