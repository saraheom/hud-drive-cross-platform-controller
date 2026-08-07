import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'windows'))
import protocol as p


def test_keep_alive_frame():
    assert p.hexstr(p.cmd_keep_alive()) == '02 7D 7F 0F 00 03'


def test_navigation_on_frame():
    assert p.hexstr(p.cmd_nav_state(True)) == '02 7D 7F 65 00 00 00 00 01 03'


def test_auto_brightness_frames():
    assert p.hexstr(p.cmd_auto_brightness(True)) == '02 7D 7F 7D 7F 01 01 03'
    assert p.hexstr(p.cmd_auto_brightness(False)) == '02 7D 7F 7D 7F 01 00 03'


def test_maneuver_contains_expected_header_and_chunks():
    packet = p.cmd_maneuver(46, 2, 2, 'Turn right\nMain St\n')
    assert packet[0] == p.STX
    assert packet[-1] == p.ETX
    assert all(len(chunk) <= 19 for chunk in p.chunks(packet, 19))
    assert len(b''.join(p.chunks(packet, 19))) == len(packet)


def test_parse_hex():
    assert p.parse_hex('02, 7D-7F 03') == bytes([0x02, 0x7D, 0x7F, 0x03])


def test_uart_connection_check_packet():
    assert p.hexstr(p.cmd_uart_connection_check()) == "02 7D 7F 06 00 03"


def test_uart_connection_event_detection():
    packet = bytes.fromhex("02 7D 7E 01 01 FF FF FF FF 03")
    assert p.is_uart_connection_event(packet)
    assert p.unescape_frame(packet) == bytes.fromhex("03 01 01 FF FF FF FF")
