#!/bin/sh
printf 'Content-Type: text/plain
Cache-Control: no-store

'
echo 'U2W HUD Live Frame Relay v8.14.2'
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
# Do not tear down healthy relay daemons or erase the last good frame on repeated Start.
# Field testing showed restarting the whole stack while HUD STA was already connected
# could produce Empty-network status and lose KivicCast discovery state.
start_one ingress /usr/lib/u2whud/u2whud_frame_ingress /tmp/u2whud_ingress.log
start_one discovery /usr/lib/u2whud/u2whud_discovery /tmp/u2whud_discovery.log
start_one cast /usr/lib/u2whud/u2whud_cast_relay /tmp/u2whud_cast.log
echo 'Frame ingress: 192.168.50.2:15331 persistent TCP ([u32 BE length][JPEG]).'
echo 'Persistent HUD discovery: UDP/15320; HUD MJPEG: TCP/15330.'
echo 'Repeated Start is idempotent; existing relay daemons and latest frame are preserved.'
