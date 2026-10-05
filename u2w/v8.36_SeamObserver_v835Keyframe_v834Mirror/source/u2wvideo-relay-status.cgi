#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W MainVideo v8.36 Passive Generation Seam Observer + v8.35 KeyFrame Diagnostics + unchanged v8.34 Mirror/v8.31 Relay status'
echo "v835_marker=$([ -f /etc/u2w_v8_35_bounded_keyframe.marker ] && echo YES || echo NO)"
echo "v834_mirror_marker=$([ -f /etc/u2w_v8_34_hard_bounded_mirror.marker ] && echo YES || echo NO)"
echo 'package_version=v8.35-bounded-keyframe-v834-mirror'
echo "v836_marker=$([ -f /etc/u2w_v8_36_seam_observer.marker ] && echo YES || echo NO)"
echo 'diagnostic_version=v8.36-passive-generation-seam-observer'
echo 'mirror_payload_changed_v836=NO'
echo 'raw_relay_payload_changed_v836=NO'
echo 'keyframe_ipc_discovery=PASSIVE_PROC_ONLY'
OP=/tmp/u2w_generation_seam_observer.pid
op=""; [ -f "$OP" ] && op=$(cat "$OP" 2>/dev/null)
echo "seam_observer_pid=$op"
if [ -n "$op" ] && kill -0 "$op" 2>/dev/null; then echo 'seam_observer_process=RUNNING'; else echo 'seam_observer_process=STOPPED'; fi
echo "seam_event_count=$(grep -c '^SEAM ' /tmp/u2w_mainvideo_seams.log 2>/dev/null || echo 0)"
latest=$(tail -1 /tmp/u2w_mainvideo_seams.log 2>/dev/null || true)
[ -n "$latest" ] && echo "seam_latest=$latest" || echo 'seam_latest=none'
echo 'mirror_payload_changed=NO'
echo 'raw_relay_payload_changed=NO'
echo 'keyframe_request_policy=ONE_DATAGRAM_PER_EXPLICIT_CGI_CALL_WITH_8S_ADAPTER_COOLDOWN'
echo 'keyframe_request_type=0x0C'
echo 'keyframe_request_payload_bytes=0'
echo 'keyframe_request_process_control=NO'
echo 'keyframe_helper_sha1=78859319b5cda7f8c42e7026b6f8502b3f7026f1'
K=/tmp/u2w_keyframe_request_status.txt
if [ -f "$K" ]; then
  awk -F= '/^(last_epoch|request_count|result|route|helper_exit|header_magic|header_type|payload_bytes)=/{print "keyframe_"$1"="$2}' "$K"
else
  echo 'keyframe_request_count=0'
  echo 'keyframe_result=never_requested'
fi
p=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
echo "relay_pid=$p"
if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo 'relay_process=RUNNING'; else echo 'relay_process=STOPPED'; fi
[ -f /tmp/u2w_mainvideo_live.h264 ] && echo "live_file_bytes=$(wc -c </tmp/u2w_mainvideo_live.h264 2>/dev/null)" || echo 'live_file_bytes=0'
echo "mem_free_kb=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null)"
echo 'relay_architecture=v8.34-hard-bounded-mirror-v831-raw'
echo 'relay_version=v8.34-hard-bounded-mirror-v831-raw'
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
    /^hard_cap_rotations=/{print "mirror_hard_cap_rotations="$2}
    /^resource_guard_trips=/{print "mirror_resource_guard_trips="$2}
    /^source_unlatches=/{print "mirror_source_unlatches="$2}
    /^source_relatches=/{print "mirror_source_relatches="$2}
    /^rotation_policy=/{print "mirror_rotation_policy="$2}
  ' "$S"
fi
echo "tmpfs_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $2}')"
echo "tmpfs_used_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $3}')"
echo "tmpfs_free_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
echo "live_next_bytes=$([ -f /tmp/u2w_mainvideo_live.next ] && wc -c </tmp/u2w_mainvideo_live.next 2>/dev/null || echo 0)"
