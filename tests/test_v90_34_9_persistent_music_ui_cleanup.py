from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "ios/HUDController/App/AppState.swift").read_text()
MEDIA = (ROOT / "ios/HUDController/UI/MediaView.swift").read_text()
NAV26 = (ROOT / "ios/HUDController/AmbientTest/HudNavigationViewIOS26.swift").read_text()
COMMANDS = (ROOT / "ios/HUDController/Protocol/HudCommands.swift").read_text()
SETTINGS_UI = (ROOT / "ios/HUDController/UI/HudSettingsView.swift").read_text()


def test_persistent_music_reuses_stock_packets_without_firmware_write():
    assert "startPersistentMusic(mini: Bool)" in APP
    assert "persistentMusicRefreshInterval: Duration = .seconds(5)" in APP
    assert "HudCommands.musicNotification(" in APP
    assert "HudCommands.widgetsMiniState(true)" in APP
    assert "HUD PERSISTENT MUSIC" in APP
    assert "adb." not in APP[APP.index("// MARK: - Persistent stock music renderer experiment"):APP.index("func sendNativeMusicMiniTest")]


def test_experimental_persistent_music_controls_are_retired_from_media_ui():
    assert "Persistent stock music renderer" not in MEDIA
    assert 'Button("Start Full")' not in MEDIA
    assert 'Button("Start Mini")' not in MEDIA
    assert 'Button("Stop + Restore Normal HUD")' not in MEDIA
    assert "CarPlay Now Playing" in MEDIA


def test_obsolete_navigation_diagnostic_cards_are_removed_from_ios26_ui():
    for text in (
        "Ambient-light test build",
        "Manual navigation diagnostics",
        "Firmware-native lane guidance",
    ):
        assert text not in NAV26
    assert "Recorded CarPlay lane replay" not in NAV26
    assert "Navigation presentation" in NAV26
    assert "HUD Firmware Maintenance" not in NAV26
    assert "HUD Firmware Maintenance" in SETTINGS_UI


def test_stock_music_wire_commands_remain_available():
    assert "notificationPacket(" in COMMANDS
    assert "category: 12" in COMMANDS
    assert "static func widgetsMiniState" in COMMANDS
    assert "p1: 122" in COMMANDS
