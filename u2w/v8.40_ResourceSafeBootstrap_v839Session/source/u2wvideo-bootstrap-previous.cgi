#!/bin/sh
# U2W v8.40 zero-copy previous-generation bootstrap.
# The observer owns one bounded previous-generation file. CGI pins it twice and
# validates its recorded SHA before streaming; it creates no private H.264 copy.
PREV=/tmp/u2w_v838_bootstrap_previous.h264
META=/tmp/u2w_v838_bootstrap_previous.meta
if [ ! -s "$PREV" ] || [ ! -s "$META" ]; then
  printf 'Status: 204 No Content\r\nCache-Control: no-store\r\n\r\n'
  exit 0
fi
attempt=0
while [ "$attempt" -lt 2 ]; do
  attempt=$((attempt+1))
  exec 9<"$PREV" || break
  exec 8<"$PREV" || { exec 9<&-; break; }
  ino9=$(stat -Lc %i /proc/$$/fd/9 2>/dev/null || echo 0)
  ino8=$(stat -Lc %i /proc/$$/fd/8 2>/dev/null || echo 0)
  N=$(stat -Lc %s /proc/$$/fd/8 2>/dev/null || echo 0)
  META_TEXT=$(cat "$META" 2>/dev/null)
  EXPECTED=$(printf '%s\n' "$META_TEXT" | awk -F= '/^sha1=/{print $2}' | tail -1)
  OLDGEN=$(printf '%s\n' "$META_TEXT" | awk -F= '/^old_generation=/{print $2}' | tail -1)
  NEXTGEN=$(printf '%s\n' "$META_TEXT" | awk -F= '/^new_generation=/{print $2}' | tail -1)
  SHA=$(sha1sum /proc/$$/fd/9 2>/dev/null | awk '{print $1}')
  if [ "$N" -gt 0 ] && [ "$ino9" = "$ino8" ] && [ "$ino8" != 0 ] && [ -n "$EXPECTED" ] && [ "$SHA" = "$EXPECTED" ] && [ -n "$OLDGEN" ] && [ -n "$NEXTGEN" ]; then
    printf 'Content-Type: application/octet-stream\r\nCache-Control: no-store\r\nContent-Length: %s\r\nX-U2W-Bootstrap: previous-v8.40-zero-copy\r\nX-U2W-Generation: %s\r\nX-U2W-Next-Generation: %s\r\nX-U2W-SHA1: %s\r\nX-U2W-Snapshot-Allocation: zero-copy-pinned-inode\r\n\r\n' "$N" "$OLDGEN" "$NEXTGEN" "$SHA"
    head -c "$N" /proc/$$/fd/8 2>/dev/null
    exec 8<&-; exec 9<&-
    exit 0
  fi
  exec 8<&-; exec 9<&-
done
printf 'Status: 503 Service Unavailable\r\nCache-Control: no-store\r\nX-U2W-Bootstrap-Error: previous-meta-race\r\n\r\n'
