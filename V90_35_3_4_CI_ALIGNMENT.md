# v90.35.3.4 CI alignment

Runtime behavior is identical to v90.35.3.3.

GitHub Actions/XCTest exposed three legacy `HudProtocolFrameTests` that used raw `0x02` as payload data. On the HUD wire protocol, literal STX/ETX/ESC payload bytes are escaped, so an unescaped STX is a frame boundary. The v90.35.3.3 nested-frame resynchronization implementation is therefore correct; the old fixtures were invalid.

This revision updates only those test fixtures to use ordinary payload bytes (or the escaped STX representation). The nested-frame recovery and escaped-STX regression tests remain unchanged.
