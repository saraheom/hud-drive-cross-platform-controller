#!/bin/sh
# Intentionally lightweight: this endpoint is advisory health, never part of the
# long-lived video data path. Do not enumerate listeners or dump a long log on every poll.
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo Lightweight Live-Edge IDR Relay v8.27 status'
echo "marker=$([ -f /etc/u2w_v8_27_live_edge_idr.marker ] && echo YES || echo NO)"
p=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
echo "relay_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'relay_process=RUNNING'; else echo 'relay_process=STOPPED'; fi
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo 'gop_cache_file_bytes=0'
echo "mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo '--- relay state ---'
cat /tmp/u2w_h264_relay_status.txt 2>/dev/null || true
