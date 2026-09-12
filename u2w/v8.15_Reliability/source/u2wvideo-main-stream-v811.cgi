#!/bin/sh
FILE=/tmp/u2w_mainvideo_live.h264
printf 'Content-Type: video/H264\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nX-U2W-Video-Format: Annex-B-H264\r\n\r\n'
i=0
while [ ! -s "$FILE" ] && [ "$i" -lt 100 ]; do sleep 1; i=$((i+1)); done
[ -s "$FILE" ] || exit 0
# Send the current decoder-friendly rolling segment, then follow appended bytes.
# The shim truncates the same inode only at a fresh SPS after ~12 MiB.
cat "$FILE"
tail -c 0 -f "$FILE"
