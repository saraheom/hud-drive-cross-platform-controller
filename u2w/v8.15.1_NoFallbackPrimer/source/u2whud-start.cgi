#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W HUD Live Frame Relay v8.15.1'
SID=0
[ -f /tmp/u2whud_session_id ] && SID=$(cat /tmp/u2whud_session_id 2>/dev/null)
case "$SID" in ''|*[!0-9]*) SID=0;; esac
SID=$((SID+1))
echo "$SID" > /tmp/u2whud_session_id
rm -f /tmp/u2whud_session_discovery /tmp/u2whud_session_client \
      /tmp/u2whud_session_established /tmp/u2whud_session_fallback \
      /tmp/u2whud_session_live
printf '\n=== session=%s start ===\n' "$SID" >>/tmp/u2whud_discovery.log
printf '\n=== session=%s start ===\n' "$SID" >>/tmp/u2whud_cast.log
printf '\n=== session=%s start ===\n' "$SID" >>/tmp/u2whud_ingress.log
start_one(){
  name="$1"; bin="$2"; log="$3"; pf="/tmp/u2whud_${name}.pid"
  old=""; [ -f "$pf" ] && old=$(cat "$pf" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    echo "${name}_pid=$old reused=1"
    return 0
  fi
  rm -f "$pf"
  "$bin" >>"$log" 2>&1 &
  pid=$!; echo "$pid" >"$pf"
  echo "${name}_pid=$pid reused=0"
}
start_one ingress /usr/lib/u2whud/u2whud_frame_ingress /tmp/u2whud_ingress.log
start_one discovery /usr/lib/u2whud/u2whud_discovery /tmp/u2whud_discovery.log
start_one cast /usr/lib/u2whud/u2whud_cast_relay /tmp/u2whud_cast.log
echo "session_id=$SID"
echo 'Frame ingress: 192.168.50.2:15331 persistent TCP ([u32 BE length][JPEG]).'
echo 'Persistent HUD discovery: UDP/15320; HUD MJPEG: TCP/15330.'
echo 'v8.15.1 uses session-scoped discovery/client/live-frame markers; healthy relay daemons are preserved across HUD display Stop/Start.'
