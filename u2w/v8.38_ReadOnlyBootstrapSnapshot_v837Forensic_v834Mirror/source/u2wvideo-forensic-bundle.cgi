#!/bin/sh
TMP=/tmp/u2w_v837_forensic_bundle_$$.tar.gz
cleanup(){ rm -f "$TMP"; }
trap cleanup EXIT INT TERM
# Parked/export-time read only. It does not signal or restart any process.
cd /tmp || exit 1
items=''
for p in u2w_mainvideo_seams.log u2w_keyframe_ipc_topology.txt u2w_mainvideo_status.txt u2w_mainvideo_relay.log u2w_v837_seam_evidence u2w_v838_bootstrap_previous.meta; do
  [ -e "$p" ] && items="$items $p"
done
if [ -z "$items" ]; then
  printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
  echo 'no v8.38/v8.37 forensic evidence present'
  exit 0
fi
# shellcheck disable=SC2086
tar -czf "$TMP" $items 2>/dev/null || {
  printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
  echo 'forensic bundle creation failed'
  exit 0
}
size=$(wc -c < "$TMP" 2>/dev/null || echo 0)
printf 'Content-Type: application/gzip\r\nCache-Control: no-store\r\nContent-Disposition: attachment; filename="U2W_v8.38_ForensicAndBootstrap.tar.gz"\r\nContent-Length: %s\r\n\r\n' "$size"
cat "$TMP"
