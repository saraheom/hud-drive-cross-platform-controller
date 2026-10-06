#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
PF=/tmp/u2w_mainvideo_relay.pid
BIN=/usr/lib/u2wvideo/u2w_mainvideo_relay
old=""; [ -f "$PF" ] && old=$(cat "$PF" 2>/dev/null)
reuse=0
if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
  exe=$(readlink "/proc/$old/exe" 2>/dev/null || true)
  [ "$exe" = "$BIN" ] && reuse=1
fi
if [ "$reuse" = 1 ]; then
  echo "relay_pid=$old reused=1"
else
  [ -n "$old" ] && kill "$old" 2>/dev/null || true
  rm -f "$PF" /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new /tmp/u2w_mainvideo_validated_gop.cache
  "$BIN" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
  pid=$!; echo "$pid" > "$PF"
  echo "relay_pid=$pid reused=0"
fi
echo 'relay_architecture=v8.27-live-edge-idr'
echo 'relay_port=15332'
echo 'wire=U2WH2645+[u32BE length][NAL], length=0 heartbeat'
echo 'bootstrap=next-validated-live-idr-only'
echo 'historical_gop_scan=0'
echo 'persistent_gop_cache=0'
echo 'generation_policy=preserve-parser-and-codec-state-across-v8.11-file-rotations'
