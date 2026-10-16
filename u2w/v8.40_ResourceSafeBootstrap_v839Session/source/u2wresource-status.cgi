#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W Resource Safety v8.40'
echo 'v840_marker=YES'
echo 'bootstrap_snapshot_policy=ZERO_COPY_PINNED_INODE_FIXED_PREFIX'
echo 'bootstrap_request_temp_h264=NONE'
set -- $(df -k /tmp 2>/dev/null | awk 'NR==2{print $2,$3,$4,$5}')
echo "tmpfs_kb=${1:-0}"
echo "tmpfs_used_kb=${2:-0}"
echo "tmpfs_free_kb=${3:-0}"
echo "tmpfs_use_percent=${4:-?}"
echo "bootstrap_previous_bytes=$([ -f /tmp/u2w_v838_bootstrap_previous.h264 ] && wc -c </tmp/u2w_v838_bootstrap_previous.h264 2>/dev/null || echo 0)"
# Legacy per-request H.264 copies are forbidden in v8.40. Report any residue.
legacy_count=$(find /tmp -maxdepth 1 -type f \( -name 'u2w_v838_bootstrap_current_*.h264' -o -name 'u2w_v838_bootstrap_previous_[0-9]*.h264' \) 2>/dev/null | wc -l)
legacy_bytes=$(find /tmp -maxdepth 1 -type f \( -name 'u2w_v838_bootstrap_current_*.h264' -o -name 'u2w_v838_bootstrap_previous_[0-9]*.h264' \) -exec wc -c {} \; 2>/dev/null | awk '{s+=$1}END{print s+0}')
echo "legacy_bootstrap_temp_count=$legacy_count"
echo "legacy_bootstrap_temp_bytes=$legacy_bytes"
echo "route_json_bytes=$([ -f /tmp/u2w_rgd_live.json ] && wc -c </tmp/u2w_rgd_live.json 2>/dev/null || echo 0)"
echo "route_status_bytes=$([ -f /tmp/u2w_rgd_status.txt ] && wc -c </tmp/u2w_rgd_status.txt 2>/dev/null || echo 0)"
echo '--- route resource counters ---'
grep '^resource_' /tmp/u2w_rgd_status.txt 2>/dev/null || true
echo '--- largest /tmp files ---'
find /tmp -maxdepth 1 -type f -exec wc -c {} \; 2>/dev/null | sort -nr | head -20
