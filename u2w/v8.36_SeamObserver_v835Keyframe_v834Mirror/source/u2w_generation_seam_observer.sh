#!/bin/sh
# Passive v8.36 observer: never opens TCP/15332, never writes the H264 mirror,
# and never signals/restarts AppleCarPlay, ARMiPhoneIAP2, or the raw relay.
LIVE=/tmp/u2w_mainvideo_live.h264
LOG=/tmp/u2w_mainvideo_seams.log
TOPO=/tmp/u2w_keyframe_ipc_topology.txt
PF=/tmp/u2w_generation_seam_observer.pid
RPF=/tmp/u2w_mainvideo_relay.pid
printf '%s\n' $$ > "$PF"
cleanup(){ rm -f "$PF"; exec 9<&- 2>/dev/null || true; }
trap cleanup EXIT INT TERM

snapshot_topology(){
  now=$(date +%s 2>/dev/null || echo 0)
  {
    echo "epoch=$now"
    echo 'note=passive /proc snapshot; no socket connect/write performed'
    grep -E '/var/run/(adb-driver|phonemirror)' /proc/net/unix 2>/dev/null || true
    for n in ARMadb-driver AppleCarPlay ARMiPhoneIAP2 fakeiOSDevice; do
      pid=$(pidof "$n" 2>/dev/null | awk '{print $1}')
      [ -n "$pid" ] || continue
      echo "process=$n pid=$pid"
      for fd in /proc/$pid/fd/*; do
        [ -e "$fd" ] || continue
        t=$(readlink "$fd" 2>/dev/null || true)
        case "$t" in socket:\[*\]) echo "fd=$(basename "$fd") target=$t";; esac
      done
    done
  } > "$TOPO.new"
  mv "$TOPO.new" "$TOPO"
}

snapshot_topology
idle=0
while [ ! -f "$LIVE" ]; do
  rp=""; [ -f "$RPF" ] && rp=$(cat "$RPF" 2>/dev/null)
  if [ -z "$rp" ] || ! kill -0 "$rp" 2>/dev/null; then
    idle=$((idle+1)); [ "$idle" -ge 20 ] && exit 0
  else idle=0; fi
  sleep 1
done
exec 9<"$LIVE" || exit 0
old_inode=$(stat -Lc %i /proc/$$/fd/9 2>/dev/null || echo 0)
old_generation=$(awk -F= '/^generation=/{print $2}' /tmp/u2w_mainvideo_status.txt 2>/dev/null | tail -1)
[ -n "$old_generation" ] || old_generation=0
event=0
while :; do
  rp=""; [ -f "$RPF" ] && rp=$(cat "$RPF" 2>/dev/null)
  if [ -z "$rp" ] || ! kill -0 "$rp" 2>/dev/null; then
    idle=$((idle+1)); [ "$idle" -ge 20 ] && exit 0
  else idle=0; fi
  [ -f "$LIVE" ] || { sleep 1; continue; }
  new_inode=$(stat -Lc %i "$LIVE" 2>/dev/null || echo 0)
  if [ "$new_inode" != 0 ] && [ "$old_inode" != 0 ] && [ "$new_inode" != "$old_inode" ]; then
    event=$((event+1))
    epoch=$(date +%s 2>/dev/null || echo 0)
    old_size=$(stat -Lc %s /proc/$$/fd/9 2>/dev/null || echo 0)
    new_size=$(stat -Lc %s "$LIVE" 2>/dev/null || echo 0)
    new_generation=$(awk -F= '/^generation=/{print $2}' /tmp/u2w_mainvideo_status.txt 2>/dev/null | tail -1)
    [ -n "$new_generation" ] || new_generation=$((old_generation+1))
    old_tail_sha1=$(tail -c 256 /proc/$$/fd/9 2>/dev/null | sha1sum 2>/dev/null | awk '{print $1}')
    new_head_sha1=$(head -c 256 "$LIVE" 2>/dev/null | sha1sum 2>/dev/null | awk '{print $1}')
    old_tail64=$(tail -c 64 /proc/$$/fd/9 2>/dev/null | od -An -tx1 -v 2>/dev/null | tr -d ' \n')
    new_head64=$(head -c 64 "$LIVE" 2>/dev/null | od -An -tx1 -v 2>/dev/null | tr -d ' \n')
    relay_fd=none; relay_pos=none; relay_inode=none; relay_size=none; relay_target=none
    if [ -n "$rp" ] && [ -d "/proc/$rp/fd" ]; then
      for f in /proc/$rp/fd/*; do
        [ -e "$f" ] || continue
        t=$(readlink "$f" 2>/dev/null || true)
        case "$t" in
          *u2w_mainvideo_live.h264*)
            relay_fd=$(basename "$f")
            relay_pos=$(awk '/^pos:/{print $2}' "/proc/$rp/fdinfo/$relay_fd" 2>/dev/null)
            [ -n "$relay_pos" ] || relay_pos=unknown
            relay_inode=$(stat -Lc %i "/proc/$rp/fd/$relay_fd" 2>/dev/null || echo unknown)
            relay_size=$(stat -Lc %s "/proc/$rp/fd/$relay_fd" 2>/dev/null || echo unknown)
            relay_target=$(echo "$t" | tr ' ' '_')
            break
            ;;
        esac
      done
    fi
    echo "SEAM event=$event epoch=$epoch old_generation=$old_generation new_generation=$new_generation old_inode=$old_inode new_inode=$new_inode old_size=$old_size new_size=$new_size relay_pid=${rp:-none} relay_fd=$relay_fd relay_pos=$relay_pos relay_inode=$relay_inode relay_size=$relay_size relay_target=$relay_target old_tail256_sha1=${old_tail_sha1:-none} new_head256_sha1=${new_head_sha1:-none} old_tail64=${old_tail64:-none} new_head64=${new_head64:-none}" >> "$LOG"
    exec 9<&-
    exec 9<"$LIVE" || exit 0
    old_inode=$new_inode
    old_generation=$new_generation
    # Refresh IPC topology at every mirror generation without touching sockets.
    snapshot_topology
  fi
  sleep 1
done
