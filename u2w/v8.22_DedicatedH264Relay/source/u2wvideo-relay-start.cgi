#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
PF=/tmp/u2w_mainvideo_relay.pid
BIN=/usr/lib/u2wvideo/u2w_mainvideo_relay
# v8.22 retires the old v8.21 file-backed cache daemon.
if [ -f /tmp/u2w_mainvideo_cache.pid ]; then
  cp=$(cat /tmp/u2w_mainvideo_cache.pid 2>/dev/null)
  [ -n "$cp" ] && kill "$cp" 2>/dev/null || true
  rm -f /tmp/u2w_mainvideo_cache.pid /tmp/u2w_mainvideo_cache_ready /tmp/u2w_mainvideo_gop_cache.h264
fi
old=""; [ -f "$PF" ] && old=$(cat "$PF" 2>/dev/null)
reuse=0
if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
  exe=$(readlink "/proc/$old/exe" 2>/dev/null || true)
  [ "$exe" = "$BIN" ] && reuse=1
fi
if [ "$reuse" = 1 ]; then
  echo "relay_pid=$old reused=1"
else
  rm -f "$PF" /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new
  "$BIN" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
  pid=$!; echo "$pid" > "$PF"
  echo "relay_pid=$pid reused=0"
fi
echo 'relay_architecture=v8.22-dedicated-h264-tcp'
echo 'relay_port=15332'
echo 'wire=U2WH2641+[u32BE length][NAL]'
