#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
PF=/tmp/u2w_mainvideo_relay.pid
BIN=/usr/lib/u2wvideo/u2w_mainvideo_relay
old=""; [ -f "$PF" ] && old=$(cat "$PF" 2>/dev/null)
if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
  exe=$(readlink "/proc/$old/exe" 2>/dev/null || true)
  if [ "$exe" = "$BIN" ]; then
    echo "relay_pid=$old reused=1"
    echo 'relay_architecture=v8.32-safe-bounded-checkpoint'
    echo 'relay_port=15332'
    echo 'wire=U2WH2649+[u32BE length][validated NAL]'
    echo 'checkpoint_cap_bytes=1572864'
    echo 'historical_generation_scan=NO'
    echo 'current_mirror_startup_forward_scan=YES'
    echo 'autostart=NO'
    echo 'navigation_dependency=NONE'
    echo 'applecarplay_modified=NO'
    echo 'source_reacquire=NEVER'
    exit 0
  fi
fi
[ -n "$old" ] && kill "$old" 2>/dev/null || true
rm -f "$PF"
: >> /tmp/u2w_mainvideo_relay.log
"$BIN" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
pid=$!; echo "$pid" > "$PF"
echo "relay_pid=$pid reused=0"
echo 'relay_architecture=v8.32-safe-bounded-checkpoint'
echo 'relay_port=15332'
echo 'wire=U2WH2649+[u32BE length][validated NAL]'
echo 'checkpoint_cap_bytes=1572864'
echo 'historical_generation_scan=NO'
echo 'current_mirror_startup_forward_scan=YES'
echo 'autostart=NO'
echo 'navigation_dependency=NONE'
echo 'applecarplay_modified=NO'
echo 'source_reacquire=NEVER'
