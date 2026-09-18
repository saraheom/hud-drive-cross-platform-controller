#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
PF=/tmp/u2w_mainvideo_cache.pid
BIN=/usr/lib/u2wvideo/u2w_mainvideo_cache
old=""; [ -f "$PF" ] && old=$(cat "$PF" 2>/dev/null)
if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
  echo "cache_pid=$old reused=1"
else
  rm -f "$PF" /tmp/u2w_mainvideo_cache_ready /tmp/u2w_mainvideo_gop_cache.h264
  "$BIN" >>/tmp/u2w_mainvideo_cache.log 2>&1 &
  pid=$!; echo "$pid" > "$PF"
  echo "cache_pid=$pid reused=0"
fi
echo 'cache_architecture=v8.21-persistent-decoder-safe-gop'
