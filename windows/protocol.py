from __future__ import annotations
import struct
from dataclasses import dataclass
from datetime import datetime

STX=0x02; ETX=0x03; ESC=0x7D
SERVICE_UUID='6e400001-b5a3-f393-e0a9-e50e24dcca9e'
TX_UUID='6e400002-b5a3-f393-e0a9-e50e24dcca9e'
RX_UUID='6e400003-b5a3-f393-e0a9-e50e24dcca9e'


def java_write_utf(text: str) -> bytes:
    # Exact for ASCII/BMP strings used in testing. Modified UTF-8 differs for NUL/supplementary chars.
    raw = text.encode('utf-8')
    if len(raw) > 65535:
        raise ValueError('String too long for Java writeUTF')
    return struct.pack('>H', len(raw)) + raw


def frame(command: int, param1: int, param2: int, payload: bytes=b'') -> bytes:
    body = bytes([command & 0xff, param1 & 0xff, param2 & 0xff]) + payload
    out=bytearray([STX])
    for b in body:
        if b in (STX,ETX,ESC): out.extend((ESC,b ^ ESC))
        else: out.append(b)
    out.append(ETX)
    return bytes(out)


def chunks(data: bytes, n: int=19):
    return [data[i:i+n] for i in range(0,len(data),n)]


def cmd_keep_alive(): return frame(2,15,0)
def cmd_uart_connection_check(): return frame(2,6,0)
def cmd_nav_state(enabled: bool): return frame(2,101,0,struct.pack('>i',1 if enabled else 0))
def cmd_auto_brightness(enabled: bool): return frame(2,2,1,bytes([1 if enabled else 0]))
def cmd_manual_brightness(value: int): return frame(2,2,5,struct.pack('>i',value))
def cmd_min_brightness(value: int=50, show_setting: bool=False): return frame(2,2,4,struct.pack('>i',value)+bytes([1 if show_setting else 0]))
def cmd_day_brightness(value: int=128): return frame(2,2,2,struct.pack('>i',value))
def cmd_night_brightness(value: int=128): return frame(2,2,3,struct.pack('>i',value))
def cmd_full_screen(enabled: bool): return frame(2,8,1,bytes([1 if enabled else 0]))
def cmd_phone_name(name: str): return frame(2,123,0,java_write_utf(name))
def cmd_system_time(epoch_ms: int, timezone_id: str='America/New_York'):
    return frame(2,1,0,struct.pack('>q',epoch_ms)+java_write_utf(timezone_id))

def cmd_maneuver(distance_m: int, maneuver_type: int, direction: int, street: str,
                 initial_heading: int=0, final_heading: int=0, exit_index: int=0,
                 right_side_driving: bool=True):
    payload=(java_write_utf(street)+struct.pack('>iiiiii',maneuver_type,direction,distance_m,
             initial_heading,final_heading,exit_index)+bytes([1 if right_side_driving else 0]))
    return frame(2,100,1,payload)

MANEUVERS={
 'Straight':(2,4),'Slight right':(2,3),'Right':(2,2),'Sharp right':(2,1),
 'Slight left':(2,5),'Left':(2,6),'Sharp left':(2,7),'U-turn':(2,8),
 'Keep right':(8,3),'Keep left':(8,5),'Exit right':(7,2),'Exit left':(7,6),
 'Roundabout':(11,2),'Destination':(17,4)
}

def hexstr(data: bytes) -> str: return ' '.join(f'{b:02X}' for b in data)
def parse_hex(text: str) -> bytes:
    compact=text.replace('0x','').replace(',',' ').replace('-',' ')
    return bytes(int(x,16) for x in compact.split())


def unescape_frame(data: bytes) -> bytes:
    """Return the unescaped frame body (without STX/ETX)."""
    if len(data) < 2 or data[0] != STX or data[-1] != ETX:
        raise ValueError("Not a complete HUDWAY frame")
    out = bytearray()
    i = 1
    while i < len(data) - 1:
        b = data[i]
        if b == ESC:
            i += 1
            if i >= len(data) - 1:
                raise ValueError("Dangling escape byte")
            out.append(data[i] ^ ESC)
        else:
            out.append(b)
        i += 1
    return bytes(out)


def is_uart_connection_event(data: bytes) -> bool:
    """HUD event 3/1/1 (UartConnectionEventPacket)."""
    try:
        body = unescape_frame(data)
        return len(body) >= 3 and body[0] == 3 and body[1] == 1 and body[2] == 1
    except ValueError:
        return False
