#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
PF=/tmp/u2w_mainvideo_relay.pid
p=""; [ -f "$PF" ] && p=$(cat "$PF" 2>/dev/null)
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
  exe=$(readlink "/proc/$p/exe" 2>/dev/null || true)
  if [ "$exe" = "/usr/lib/u2wvideo/u2w_mainvideo_relay" ]; then
    kill "$p" 2>/dev/null || true
    echo "stopped_pid=$p"
  else
    echo 'stopped_pid=NONE_pidfile_not_ours'
  fi
else
  echo 'stopped_pid=NONE'
fi
rm -f "$PF"
echo 'navigation_unchanged=YES'
echo 'applecarplay_unchanged=YES'
