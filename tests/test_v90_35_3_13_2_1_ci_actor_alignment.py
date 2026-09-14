from pathlib import Path


def test_current_session_monitor_is_explicitly_main_actor_isolated():
    source = Path("ios/HUDController/App/AppState.swift").read_text()
    needle = "@MainActor\n            func monitorCurrentSession(seconds: Int, phase: String) async -> Bool"
    assert needle in source


def test_current_session_monitor_still_requires_session_scoped_client_and_live_frame():
    source = Path("ios/HUDController/App/AppState.swift").read_text()
    assert "sessionScoped ? (clientSeen && liveFrameSent) : established" in source
    assert "if relay.currentSessionReady" in source
