#!/bin/sh
# U2W v8.38 passive bootstrap-history observer boot hook.
# Starts only the read-only mirror observer; it never starts TCP/15332, never
# signals CarPlay, and never writes the live H.264 mirror.
OBS=/usr/bin/u2w_generation_seam_observer.sh
PF=/tmp/u2w_generation_seam_observer.pid
start_observer(){
  p=""; [ -f "$PF" ] && p=$(cat "$PF" 2>/dev/null)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then exit 0; fi
  rm -f "$PF"
  [ -x "$OBS" ] || exit 0
  "$OBS" >/tmp/u2w_generation_seam_observer.stdout 2>&1 &
}
stop_observer(){
  p=""; [ -f "$PF" ] && p=$(cat "$PF" 2>/dev/null)
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
  rm -f "$PF"
}
case "${1:-start}" in
  stop) stop_observer ;;
  restart) stop_observer; start_observer ;;
  *) start_observer ;;
esac
exit 0
