#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W v8.37 passive MainVideo forensic generation seam evidence'
echo 'mirror_changed=NO'
echo 'raw_relay_changed=NO'
echo 'observer_writes_h264=NO'
echo 'observer_opens_tcp15332=NO'
echo 'observer_connects_keyframe_ipc=NO'
echo 'observer_process_control=NO'
echo "forensic_dir=/tmp/u2w_v837_seam_evidence"
echo "seam_event_count=$(grep -c '^SEAM ' /tmp/u2w_mainvideo_seams.log 2>/dev/null || echo 0)"
echo "complete_boundary_samples=$(grep -c 'capture_complete=YES' /tmp/u2w_mainvideo_seams.log 2>/dev/null || echo 0)"
echo "boundary_sample_files=$(find /tmp/u2w_v837_seam_evidence -type f -name 'seam_*_*.bin' 2>/dev/null | wc -l)"
echo "boundary_sample_bytes=$(find /tmp/u2w_v837_seam_evidence -type f -name 'seam_*_*.bin' -exec wc -c {} \; 2>/dev/null | awk '{s+=$1} END{print s+0}')"
echo '--- ipc topology ---'
cat /tmp/u2w_keyframe_ipc_topology.txt 2>/dev/null || echo 'none'
echo '--- seam log ---'
cat /tmp/u2w_mainvideo_seams.log 2>/dev/null || echo 'none'
