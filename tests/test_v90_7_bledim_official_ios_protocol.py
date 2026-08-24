from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = (ROOT / "ios/HUDController/Vehicle/AmbientLightModels.swift").read_text()
MONITOR = (ROOT / "ios/HUDController/Vehicle/AmbientLightMonitor.swift").read_text()
VIEW = (ROOT / "ios/HUDController/UI/AmbientLightingView.swift").read_text()


def checksum(frame_without_checksum):
    return sum(frame_without_checksum) & 0xFF


def test_capture_frames_have_additive_checksum():
    captured = [
        [0x55, 0xAA, 0x09, 0x80, 0x00, 0x01, 0x00, 0x89],  # OFF
        [0x55, 0xAA, 0x0A, 0x80, 0x00, 0x01, 0x01, 0x8B],  # ON
        [0x55, 0xAA, 0x0B, 0x82, 0x00, 0x0C, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x80, 0x00, 0x00, 0x00, 0x16],  # red
        [0x55, 0xAA, 0x0C, 0x82, 0x00, 0x0C, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x80, 0x00, 0x00, 0x00, 0x17],  # green
        [0x55, 0xAA, 0x0E, 0x82, 0x00, 0x0C, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x80, 0x00, 0x00, 0x00, 0x19],  # blue
        [0x55, 0xAA, 0x12, 0x88, 0x00, 0x06, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA1],  # brightness 0 endpoint
        [0x55, 0xAA, 0x28, 0x88, 0x00, 0x06, 0x02, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xB6],  # brightness 100 endpoint
    ]
    for frame in captured:
        assert checksum(frame[:-1]) == frame[-1]


def test_swift_protocol_matches_captured_frame_grammar():
    assert "0x55, 0xAA, sequence, command" in MODEL
    assert "UInt8((length >> 8) & 0xFF)" in MODEL
    assert "UInt8(length & 0xFF)" in MODEL
    assert "UInt8(truncatingIfNeeded: bytes.reduce(0)" in MODEL
    assert "payload: [on ? 0x01 : 0x00]" in MODEL
    assert "command: 0x80" in MODEL
    assert "command: 0x82" in MODEL
    assert "command: 0x88" in MODEL
    assert "0x00, UInt8(rgb.red), UInt8(rgb.green), UInt8(rgb.blue)" in MODEL
    assert "payload: [0x02, value, 0x00, 0x00, 0x00, 0x00]" in MODEL


def test_brightness_maps_user_percent_to_captured_0_255_channel():
    assert "Double(clamped) * 255.0 / 100.0" in MODEL


def test_bledim_is_reenabled_for_normal_control_and_vehicle_automation():
    control_block = MONITOR.split("func isControllable", 1)[1].split("func isBLEDIMRawTransportReady", 1)[0]
    assert "device.protocolKind == .bledim2 { return false }" not in control_block
    assert "BLEDIM2Protocol.power" in MONITOR
    assert "BLEDIM2Protocol.color" in MONITOR
    assert "BLEDIM2Protocol.brightness" in MONITOR
    assert "nextBLEDIMSequence" in MONITOR
    assert "runStartupAnimationIfNeeded(id)" in MONITOR
    assert "bledimUndecoded" not in VIEW


def test_old_guessed_7e_ff_family_stays_retired():
    assert "0x7E, 0xFF, 0x04" not in MODEL
    assert "0x7E, 0xFF, 0x05" not in MODEL
    assert "0x7E, 0xFF, 0x01" not in MODEL
