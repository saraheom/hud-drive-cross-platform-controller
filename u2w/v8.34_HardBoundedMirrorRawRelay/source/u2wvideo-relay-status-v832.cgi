#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo Safe Bounded Checkpoint Relay v8.32 status'
echo "marker=$([ -f /etc/u2w_v8_32_safe_checkpoint.marker ] && echo YES || echo NO)"
p=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
echo "relay_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'relay_process=RUNNING'; else echo 'relay_process=STOPPED'; fi
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo "mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo 'relay_architecture=v8.32-safe-bounded-checkpoint'
echo 'relay_version=v8.32-safe-bounded-checkpoint'
echo 'wire_magic=U2WH2649'
echo 'adapter_h264_parser=VALIDATOR_ONLY'
echo 'adapter_video_cache=BOUNDED_CURRENT_CHECKPOINT'
echo 'checkpoint_cap_bytes=1572864'
echo 'historical_generation_scan=NO'
echo 'current_mirror_startup_forward_scan=YES'
echo 'source_reacquire=NEVER'
echo 'relay_autostart=NO'
echo 'navigation_dependency=NONE'
echo 'applecarplay_modified=NO'
echo 'route_guidance_changed=NO'
[ -f /tmp/u2w_h264_relay_status.txt ] && cat /tmp/u2w_h264_relay_status.txt
