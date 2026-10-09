#!/bin/sh
PREV=/tmp/u2w_v838_bootstrap_previous.h264
META=/tmp/u2w_v838_bootstrap_previous.meta
TMP=/tmp/u2w_v838_bootstrap_previous_$$.h264
MTMP=/tmp/u2w_v838_bootstrap_previous_$$.meta
cleanup(){ rm -f "$TMP" "$MTMP"; }
trap cleanup EXIT INT TERM
if [ ! -s "$PREV" ] || [ ! -s "$META" ]; then
  printf 'Status: 204 No Content\r\nCache-Control: no-store\r\n\r\n'
  exit 0
fi
# PREV and META are replaced independently by the passive observer. Make private
# copies and verify the recorded SHA so a rotation race can never return a
# mismatched generation pair to the iPhone.
attempt=0
while [ "$attempt" -lt 2 ]; do
  attempt=$((attempt+1))
  if cat "$PREV" > "$TMP" 2>/dev/null && cat "$META" > "$MTMP" 2>/dev/null; then
    N=$(wc -c < "$TMP" 2>/dev/null || echo 0)
    SHA=$(sha1sum "$TMP" 2>/dev/null | awk '{print $1}')
    EXPECTED=$(awk -F= '/^sha1=/{print $2}' "$MTMP" 2>/dev/null | tail -1)
    OLDGEN=$(awk -F= '/^old_generation=/{print $2}' "$MTMP" 2>/dev/null | tail -1)
    NEXTGEN=$(awk -F= '/^new_generation=/{print $2}' "$MTMP" 2>/dev/null | tail -1)
    if [ "$N" -gt 0 ] && [ -n "$EXPECTED" ] && [ "$SHA" = "$EXPECTED" ] && [ -n "$OLDGEN" ] && [ -n "$NEXTGEN" ]; then
      printf 'Content-Type: application/octet-stream\r\nCache-Control: no-store\r\nContent-Length: %s\r\nX-U2W-Bootstrap: previous-v8.38\r\nX-U2W-Generation: %s\r\nX-U2W-Next-Generation: %s\r\nX-U2W-SHA1: %s\r\n\r\n' "$N" "$OLDGEN" "$NEXTGEN" "$SHA"
      cat "$TMP"
      exit 0
    fi
  fi
  rm -f "$TMP" "$MTMP"
done
printf 'Status: 503 Service Unavailable\r\nCache-Control: no-store\r\nX-U2W-Bootstrap-Error: previous-meta-race\r\n\r\n'
