#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W HUD Live Frame Relay v8.39 fresh-session start'
SID=0
[ -f /tmp/u2whud_session_id ] && SID=$(cat /tmp/u2whud_session_id 2>/dev/null)
case "$SID" in ''|*[!0-9]*) SID=0;; esac
SID=$((SID+1)); echo "$SID" >/tmp/u2whud_session_id
rm -f /tmp/u2whud_session_discovery /tmp/u2whud_session_client /tmp/u2whud_session_established /tmp/u2whud_session_fallback /tmp/u2whud_session_live
printf '\n=== v8.39 fresh session=%s start ===\n' "$SID" >>/tmp/u2whud_discovery.log
printf '\n=== v8.39 fresh session=%s start ===\n' "$SID" >>/tmp/u2whud_cast.log
printf '\n=== v8.39 fresh session=%s start ===\n' "$SID" >>/tmp/u2whud_ingress.log
stop_one(){
  name="$1"; pf="/tmp/u2whud_${name}.pid"; old=""
  [ -f "$pf" ] && old=$(cat "$pf" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    kill "$old" 2>/dev/null || true
    i=0; while kill -0 "$old" 2>/dev/null && [ "$i" -lt 12 ]; do sleep 0.1; i=$((i+1)); done
    kill -0 "$old" 2>/dev/null && kill -9 "$old" 2>/dev/null || true
  fi
  rm -f "$pf"
}
start_one(){
  name="$1"; bin="$2"; log="$3"; pf="/tmp/u2whud_${name}.pid"
  "$bin" >>"$log" 2>&1 & pid=$!; echo "$pid" >"$pf"
  echo "${name}_pid=$pid reused=0 fresh_session=YES"
}
# v8.39 deliberately retires ONLY the custom HUD helpers. AppleCarPlay,
# MainVideo mirror/raw relay and Route Guidance processes are never signaled here.
stop_one ingress; stop_one discovery; stop_one cast
start_one ingress /usr/lib/u2whud/u2whud_frame_ingress /tmp/u2whud_ingress.log
start_one discovery /usr/lib/u2whud/u2whud_discovery /tmp/u2whud_discovery.log
start_one cast /usr/lib/u2whud/u2whud_cast_relay /tmp/u2whud_cast.log
echo "session_id=$SID"
echo 'fresh_helpers=YES'
echo 'applecarplay_process_control=NEVER'
echo 'mainvideo_process_control=NEVER'
echo 'Frame ingress: 192.168.50.2:15331 persistent TCP ([u32 BE length][JPEG]).'
