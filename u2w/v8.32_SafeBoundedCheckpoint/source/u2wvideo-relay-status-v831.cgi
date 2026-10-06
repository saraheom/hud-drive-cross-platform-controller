#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo Navigation-Priority Raw Relay v8.31 status'
echo "marker=$([ -f /etc/u2w_v8_31_navigation_priority_raw.marker ] && echo YES || echo NO)"
p=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
echo "relay_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'relay_process=RUNNING'; else echo 'relay_process=STOPPED'; fi
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo "mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo 'relay_architecture=v8.31-navigation-priority-raw'
echo 'relay_version=v8.31-navigation-priority-raw'
echo 'wire_magic=U2WH2648'
echo 'raw_buffer_bytes=32768'
echo 'adapter_h264_parser=NO'
echo 'adapter_video_cache=NO'
echo 'adapter_reference_chain=NO'
echo 'relay_autostart=NO'
echo 'navigation_dependency=NONE'
echo 'applecarplay_modified=NO'
echo 'route_guidance_changed=NO'
echo "v830_boot_helper_initd=$([ -e /etc/init.d/S99u2w_mainvideo_v830 ] && echo PRESENT || echo ABSENT)"
echo "v830_boot_helper_rcSd=$([ -e /etc/rcS.d/S99u2w_mainvideo_v830 ] && echo PRESENT || echo ABSENT)"
