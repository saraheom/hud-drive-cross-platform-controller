#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo v8.33 Lossless Mirror + v8.31 Raw Relay status'
echo "marker=$([ -f /etc/u2w_v8_33_lossless_mirror.marker ] && echo YES || echo NO)"
p=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
echo "relay_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'relay_process=RUNNING'; else echo 'relay_process=STOPPED'; fi
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo "mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo 'relay_architecture=v8.33-lossless-mirror-v831-raw'
echo 'relay_version=v8.33-lossless-mirror-v831-raw'
echo 'wire_magic=U2WH2648'
echo 'raw_buffer_bytes=32768'
echo 'adapter_h264_parser=NO'
echo 'adapter_video_cache=NO'
echo 'adapter_reference_chain=NO'
echo 'relay_autostart=NO'
echo 'navigation_dependency=NONE'
echo 'applecarplay_process_control=NO'
echo 'route_guidance_changed=NO'
S=/tmp/u2w_mainvideo_status.txt
if [ -f "$S" ]; then
  awk -F= '
    /^exporter_version=/{print "mirror_version="$2}
    /^generation=/{print "mirror_generation="$2}
    /^segment_bytes=/{print "mirror_segment_bytes="$2}
    /^total_mirrored_bytes=/{print "mirror_total_bytes="$2}
    /^rotation_attempts=/{print "mirror_rotation_attempts="$2}
    /^rotation_success=/{print "mirror_rotation_success="$2}
    /^rotation_fallback_append=/{print "mirror_rotation_fallback_append="$2}
    /^rotation_prefix_preserved_bytes=/{print "mirror_prefix_preserved_bytes="$2}
    /^mirror_partial_write_retries=/{print "mirror_partial_write_retries="$2}
    /^mirror_write_failures=/{print "mirror_write_failures="$2}
    /^rotation_policy=/{print "mirror_rotation_policy="$2}
  ' "$S"
fi
echo "v830_boot_helper_initd=$([ -e /etc/init.d/S99u2w_mainvideo_v830 ] && echo PRESENT || echo ABSENT)"
echo "v830_boot_helper_rcSd=$([ -e /etc/rcS.d/S99u2w_mainvideo_v830 ] && echo PRESENT || echo ABSENT)"
