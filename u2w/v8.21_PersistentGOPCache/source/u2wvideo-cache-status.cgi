#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo GOP Cache v8.21 status'
echo "marker=$([ -f /etc/u2w_v8_21_gop_cache.marker ] && echo YES || echo NO)"
p=""; [ -f /tmp/u2w_mainvideo_cache.pid ] && p=$(cat /tmp/u2w_mainvideo_cache.pid 2>/dev/null)
echo "cache_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'cache_process=RUNNING'; else echo 'cache_process=STOPPED'; fi
[ -s /tmp/u2w_mainvideo_cache_ready ] && echo 'cache_ready=YES' || echo 'cache_ready=NO'
[ -f /tmp/u2w_mainvideo_gop_cache.h264 ] && echo "cache_bytes=$(wc -c </tmp/u2w_mainvideo_gop_cache.h264 2>/dev/null)" || echo 'cache_bytes=0'
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo "stream_cgi_processes=$(ps 2>/dev/null | grep '[u]2w_mainvideo_streamer' | wc -l)"
echo "route_json_bytes=$([ -f /tmp/u2w_rgd_live.json ] && wc -c </tmp/u2w_rgd_live.json 2>/dev/null || echo 0)"
echo "media_json_bytes=$([ -f /tmp/u2w_media_live.json ] && wc -c </tmp/u2w_media_live.json 2>/dev/null || echo 0)"
echo '--- cache log ---'
tail -n 24 /tmp/u2w_mainvideo_cache.log 2>/dev/null || true
