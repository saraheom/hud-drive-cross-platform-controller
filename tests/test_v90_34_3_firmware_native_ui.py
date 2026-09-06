from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def test_native_lane_packet_matches_decompiled_hudlauncher():
    src = text("ios/HUDController/Protocol/HudCommands.swift")
    assert "p1: 113, p2: 0" in src
    assert "case straight = 1" in src
    assert "case right = 2" in src
    assert "case straightRight = 3" in src
    assert "case left = 4" in src
    assert "case straightLeft = 5" in src
    assert "recommended ? type.rawValue : -type.rawValue" in src

def test_native_lane_diagnostics_are_manual_only():
    app = text("ios/HUDController/App/AppState.swift")
    nav = text("ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift")
    route = text("ios/HUDController/Navigation/RouteGuidanceAdapterClient.swift")
    assert "sendNativeLaneTest" in app
    assert "Send Lane Test" in nav
    assert "clearNativeLaneTest" in app
    assert "HudCommands.laneGuidance" not in route

def test_mini_music_uses_stock_ble_packets_and_has_restore():
    app = text("ios/HUDController/App/AppState.swift")
    media = text("ios/HUDController/UI/MediaView.swift")
    assert "HudCommands.widgetsMiniState(true)" in app
    assert "HudCommands.widgetsMiniState(false)" in app
    assert "HudCommands.musicNotification(" in app
    assert "Mini Music ON + Send" in media
    assert "Restore Normal UI" in media
    start = app.index("func sendNativeMusicMiniTest")
    end = app.index("func sendNativeMusicTest", start)
    music_block = app[start:end].lower()
    for forbidden in ("adb ", "remount", "system/media/bootanimation.zip"):
        assert forbidden not in music_block
