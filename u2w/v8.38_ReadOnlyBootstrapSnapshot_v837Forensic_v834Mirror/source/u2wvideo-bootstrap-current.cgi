#!/bin/sh
LIVE=/tmp/u2w_mainvideo_live.h264
STATUS=/tmp/u2w_mainvideo_status.txt
TMP=/tmp/u2w_v838_bootstrap_current_$$.h264
cleanup(){ rm -f "$TMP"; }
trap cleanup EXIT INT TERM
if [ ! -s "$LIVE" ]; then
  printf 'Status: 204 No Content\r\nCache-Control: no-store\r\n\r\n'
  exit 0
fi
# A private copy gives HTTP a stable read-only prefix while the source keeps
# appending to the live mirror. Reject a copy if the mirror inode/generation
# rotates while it is being captured; the iPhone will simply retry/fall back.
attempt=0
while [ "$attempt" -lt 2 ]; do
  attempt=$((attempt+1))
  ino_before=$(stat -Lc %i "$LIVE" 2>/dev/null || echo 0)
  gen_before=$(awk -F= '/^generation=/{print $2}' "$STATUS" 2>/dev/null | tail -1)
  [ -n "$gen_before" ] || gen_before=0
  if cat "$LIVE" > "$TMP" 2>/dev/null; then
    ino_after=$(stat -Lc %i "$LIVE" 2>/dev/null || echo 0)
    gen_after=$(awk -F= '/^generation=/{print $2}' "$STATUS" 2>/dev/null | tail -1)
    [ -n "$gen_after" ] || gen_after=0
    N=$(wc -c < "$TMP" 2>/dev/null || echo 0)
    if [ "$N" -gt 0 ] && [ "$ino_before" = "$ino_after" ] && [ "$ino_before" != 0 ] && [ "$gen_before" = "$gen_after" ]; then
      SHA=$(sha1sum "$TMP" 2>/dev/null | awk '{print $1}')
      printf 'Content-Type: application/octet-stream\r\nCache-Control: no-store\r\nContent-Length: %s\r\nX-U2W-Bootstrap: current-v8.38\r\nX-U2W-Generation: %s\r\nX-U2W-Inode: %s\r\nX-U2W-SHA1: %s\r\n\r\n' "$N" "$gen_before" "$ino_before" "${SHA:-none}"
      cat "$TMP"
      exit 0
    fi
  fi
  rm -f "$TMP"
done
printf 'Status: 503 Service Unavailable\r\nCache-Control: no-store\r\nX-U2W-Bootstrap-Error: generation-rotated-during-copy\r\n\r\n'
