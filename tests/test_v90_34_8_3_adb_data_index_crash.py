from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / "ios/HUDController/Firmware/HUDADBClient.swift"
TEST = ROOT / "ios/HUDControllerTests/V903483ADBDataIndexCrashTests.swift"


def test_adb_u32_decoder_is_data_start_index_relative_and_throwing():
    text = ADB.read_text()
    assert "data.index(data.startIndex, offsetBy: offset)" in text
    assert "data.count >= offset + 4" in text
    assert "throw ADBError.protocolError" in text
    assert "data[offset..<(offset + 4)]" not in text


def test_sync_and_packet_parsers_use_safe_decoder():
    text = ADB.read_text()
    assert "try Self.readUInt32LE(buffer, offset: 4)" in text
    assert "try Self.readUInt32LE(header, offset: 12)" in text


def test_regression_test_reproduces_consumed_data_prefix():
    text = TEST.read_text()
    assert "buffer.removeFirst(4)" in text
    assert "0x12345678" in text
    assert "XCTAssertThrowsError" in text
