from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_speed_information_xctest_expects_uart_escaped_p2_etx():
    src = (ROOT / "ios/HUDControllerTests/V903416TimeWeatherColdOffSpeedGaugeProbeTests.swift").read_text(encoding="utf-8")
    assert '"02 7D 7F 09 7D 7E 01 03"' in src
    assert 'Data([0x02, 0x09, 0x03, 0x01])' in src
    assert '"02 7D 7F 09 03 01 03"' not in src
