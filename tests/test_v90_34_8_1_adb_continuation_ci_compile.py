from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / "ios/HUDController/Firmware/HUDADBClient.swift"


def test_adb_continuations_have_explicit_result_types_for_xcode_26():
    text = ADB.read_text()
    assert text.count("CheckedContinuation<Void, Error>") >= 2
    assert "CheckedContinuation<Data, Error>" in text
    assert "let chunk: Data = try await withCheckedThrowingContinuation" in text


def test_boot_animation_write_scope_unchanged():
    text = (ROOT / "ios/HUDController/Firmware/HudMaintenanceManager.swift").read_text()
    assert 'static let remoteDirectory = "/data/local/bootanimation"' in text
    assert 'static let remoteOverride = "/data/local/bootanimation/bootanimation.zip"' in text
    assert r'adb.shell("mv \(Self.remotePending) \(Self.remoteOverride)' in text
    assert r'adb.shell("rm -f \(Self.remoteOverride) \(Self.remotePending)' in text
    # /system is referenced only in explanatory UI text; no shell command writes it.
    for line in text.splitlines():
        if "adb.shell(" in line:
            assert "/system/" not in line
