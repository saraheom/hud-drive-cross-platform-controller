#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo Dedicated H264 Relay v8.22 status'
echo "marker=$([ -f /etc/u2w_v8_22_h264_relay.marker ] && echo YES || echo NO)"
p=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
echo "relay_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'relay_process=RUNNING'; else echo 'relay_process=STOPPED'; fi
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo "legacy_cache_processes=$(ps 2>/dev/null | grep '[u]2w_mainvideo_cache' | wc -l)"
echo "legacy_stream_cgi_processes=$(ps 2>/dev/null | grep '[u]2w_mainvideo_streamer' | wc -l)"
echo "mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo "mem_cached_kb=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo "route_json_bytes=$([ -f /tmp/u2w_rgd_live.json ] && wc -c </tmp/u2w_rgd_live.json 2>/dev/null || echo 0)"
echo "media_json_bytes=$([ -f /tmp/u2w_media_live.json ] && wc -c </tmp/u2w_media_live.json 2>/dev/null || echo 0)"
echo '--- relay state ---'
cat /tmp/u2w_h264_relay_status.txt 2>/dev/null || true
echo '--- listeners ---'
netstat -lntp 2>&1 | grep -E '(:80 |:15330 |:15331 |:15332 )' || true
echo '--- relay log ---'
tail -n 32 /tmp/u2w_mainvideo_relay.log 2>/dev/null || true
