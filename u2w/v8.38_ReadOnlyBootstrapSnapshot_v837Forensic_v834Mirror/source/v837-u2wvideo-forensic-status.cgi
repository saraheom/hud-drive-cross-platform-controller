#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
E=/tmp/u2w_v837_seam_evidence
L=/tmp/u2w_mainvideo_seams.log
events=$(grep -c '^SEAM ' "$L" 2>/dev/null || echo 0)
complete=$(grep -c 'capture_complete=YES' "$L" 2>/dev/null || echo 0)
files=$(find "$E" -type f 2>/dev/null | wc -l)
bytes=$(find "$E" -type f -exec wc -c {} \; 2>/dev/null | awk '{s+=$1} END{print s+0}')
echo 'diagnostic_version=v8.37-forensic-seam-capture'
echo "v837_marker=$([ -f /etc/u2w_v8_37_forensic_seam.marker ] && echo YES || echo NO)"
echo "v836_marker=$([ -f /etc/u2w_v8_36_seam_observer.marker ] && echo YES || echo NO)"
echo 'mirror_payload_changed=NO'
echo 'raw_relay_payload_changed=NO'
echo 'keyframe_helper_changed=NO'
echo 'opens_tcp15332=NO'
echo 'writes_h264_mirror=NO'
echo 'applecarplay_process_control=NO'
echo "seam_events=$events"
echo "complete_boundary_samples=$complete"
echo "evidence_files=$files"
echo "evidence_bytes=$bytes"
echo 'sample_bytes_per_side=4096'
echo 'retained_seam_groups=128'
latest=$(tail -1 "$L" 2>/dev/null || true)
[ -n "$latest" ] && echo "latest_seam=$latest" || echo 'latest_seam=none'
