#!/bin/sh
# U2W v8.40 zero-copy current-generation bootstrap.
# Pin the current mirror inode twice (hash/body), capture a fixed byte length,
# and stream that immutable prefix directly. No per-request H.264 copy in /tmp.
LIVE=/tmp/u2w_mainvideo_live.h264
STATUS=/tmp/u2w_mainvideo_status.txt
if [ ! -s "$LIVE" ]; then
  printf 'Status: 204 No Content\r\nCache-Control: no-store\r\n\r\n'
  exit 0
fi
attempt=0
while [ "$attempt" -lt 2 ]; do
  attempt=$((attempt+1))
  gen_before=$(awk -F= '/^generation=/{print $2}' "$STATUS" 2>/dev/null | tail -1); [ -n "$gen_before" ] || gen_before=0
  exec 9<"$LIVE" || break
  exec 8<"$LIVE" || { exec 9<&-; break; }
  ino9=$(stat -Lc %i /proc/$$/fd/9 2>/dev/null || echo 0)
  ino8=$(stat -Lc %i /proc/$$/fd/8 2>/dev/null || echo 0)
  pathino=$(stat -Lc %i "$LIVE" 2>/dev/null || echo 0)
  gen_after=$(awk -F= '/^generation=/{print $2}' "$STATUS" 2>/dev/null | tail -1); [ -n "$gen_after" ] || gen_after=0
  N=$(stat -Lc %s /proc/$$/fd/8 2>/dev/null || echo 0)
  if [ "$N" -gt 0 ] && [ "$ino9" = "$ino8" ] && [ "$ino8" = "$pathino" ] && [ "$ino8" != 0 ] && [ "$gen_before" = "$gen_after" ]; then
    SHA=$(sha1sum /proc/$$/fd/9 2>/dev/null | awk '{print $1}')
    printf 'Content-Type: application/octet-stream\r\nCache-Control: no-store\r\nContent-Length: %s\r\nX-U2W-Bootstrap: current-v8.40-zero-copy\r\nX-U2W-Generation: %s\r\nX-U2W-Inode: %s\r\nX-U2W-SHA1: %s\r\nX-U2W-Snapshot-Allocation: zero-copy-pinned-inode\r\n\r\n' "$N" "$gen_before" "$ino8" "${SHA:-none}"
    head -c "$N" /proc/$$/fd/8 2>/dev/null
    exec 8<&-; exec 9<&-
    exit 0
  fi
  exec 8<&-; exec 9<&-
done
printf 'Status: 503 Service Unavailable\r\nCache-Control: no-store\r\nX-U2W-Bootstrap-Error: generation-rotated-during-pin\r\n\r\n'
