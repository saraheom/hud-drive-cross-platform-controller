#!/bin/sh
# U2W v8.38 passive forensic seam + read-only startup bootstrap snapshot collector.
# SAFETY BOUNDARY: this process never opens TCP/15332, never writes the H.264
# mirror, never connects/writes to adb-driver or phonemirror IPC, and never
# signals/restarts AppleCarPlay, ARMiPhoneIAP2, fakeiOSDevice, or the raw relay.
LIVE=/tmp/u2w_mainvideo_live.h264
LOG=/tmp/u2w_mainvideo_seams.log
TOPO=/tmp/u2w_keyframe_ipc_topology.txt
EVID=/tmp/u2w_v837_seam_evidence
BOOT_PREV=/tmp/u2w_v838_bootstrap_previous.h264
BOOT_META=/tmp/u2w_v838_bootstrap_previous.meta
PF=/tmp/u2w_generation_seam_observer.pid
RPF=/tmp/u2w_mainvideo_relay.pid
MAX_EVENTS=128
SAMPLE_BYTES=4096
mkdir -p "$EVID" 2>/dev/null || true
printf '%s\n' $$ > "$PF"
cleanup(){ rm -f "$PF"; exec 9<&- 2>/dev/null || true; }
trap cleanup EXIT INT TERM

sha1_file(){ sha1sum "$1" 2>/dev/null | awk '{print $1}'; }

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

snapshot_relay_fds(){
  rp="$1"; out="$2"
  {
    echo "relay_pid=${rp:-none}"
    if [ -n "$rp" ] && [ -d "/proc/$rp/fd" ]; then
      for f in /proc/$rp/fd/*; do
        [ -e "$f" ] || continue
        n=$(basename "$f")
        t=$(readlink "$f" 2>/dev/null || true)
        p=$(awk '/^pos:/{print $2}' "/proc/$rp/fdinfo/$n" 2>/dev/null)
        ino=$(stat -Lc %i "$f" 2>/dev/null || echo unknown)
        sz=$(stat -Lc %s "$f" 2>/dev/null || echo unknown)
        echo "fd=$n pos=${p:-unknown} inode=$ino size=$sz target=$(echo "$t" | tr ' ' '_')"
      done
    else
      echo 'relay_fd_snapshot=unavailable'
    fi
  } > "$out"
}

snapshot_topology
# v8.38 starts this passive reader at adapter boot so the generation immediately
# preceding the app's first TCP connection can still be retained. The observer
# does not depend on the TCP relay being running; it simply waits for the mirror.
while [ ! -f "$LIVE" ]; do sleep 1; done
exec 9<"$LIVE" || exit 0
old_inode=$(stat -Lc %i /proc/$$/fd/9 2>/dev/null || echo 0)
old_generation=$(awk -F= '/^generation=/{print $2}' /tmp/u2w_mainvideo_status.txt 2>/dev/null | tail -1)
[ -n "$old_generation" ] || old_generation=0
event=$(grep -c '^SEAM ' "$LOG" 2>/dev/null || echo 0)

while :; do
  rp=""; [ -f "$RPF" ] && rp=$(cat "$RPF" 2>/dev/null)
  # Relay may legitimately be absent before Map Mode is requested. Continue
  # observing mirror generations read-only so startup history is not lost.
  if [ -n "$rp" ] && ! kill -0 "$rp" 2>/dev/null; then rp=""; fi
  [ -f "$LIVE" ] || { sleep 1; continue; }
  new_inode=$(stat -Lc %i "$LIVE" 2>/dev/null || echo 0)
  if [ "$new_inode" != 0 ] && [ "$old_inode" != 0 ] && [ "$new_inode" != "$old_inode" ]; then
    event=$((event+1))
    tag=$(printf '%04d' "$event")
    epoch=$(date +%s 2>/dev/null || echo 0)
    old_size=$(stat -Lc %s /proc/$$/fd/9 2>/dev/null || echo 0)
    new_size=$(stat -Lc %s "$LIVE" 2>/dev/null || echo 0)
    new_generation=$(awk -F= '/^generation=/{print $2}' /tmp/u2w_mainvideo_status.txt 2>/dev/null | tail -1)
    [ -n "$new_generation" ] || new_generation=$((old_generation+1))

    old_sample="$EVID/seam_${tag}_old_tail_${SAMPLE_BYTES}.bin"
    new_sample="$EVID/seam_${tag}_new_head_${SAMPLE_BYTES}.bin"
    tail -c "$SAMPLE_BYTES" /proc/$$/fd/9 > "$old_sample" 2>/dev/null || : > "$old_sample"
    head -c "$SAMPLE_BYTES" "$LIVE" > "$new_sample" 2>/dev/null || : > "$new_sample"
    old_sample_bytes=$(wc -c < "$old_sample" 2>/dev/null || echo 0)
    new_sample_bytes=$(wc -c < "$new_sample" 2>/dev/null || echo 0)
    old_sample_sha1=$(sha1_file "$old_sample")
    new_sample_sha1=$(sha1_file "$new_sample")
    old_tail_sha1=$(tail -c 256 /proc/$$/fd/9 2>/dev/null | sha1sum 2>/dev/null | awk '{print $1}')
    new_head_sha1=$(head -c 256 "$LIVE" 2>/dev/null | sha1sum 2>/dev/null | awk '{print $1}')

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

    snapshot_relay_fds "$rp" "$EVID/seam_${tag}_relay_fds.txt"
    cp /tmp/u2w_mainvideo_status.txt "$EVID/seam_${tag}_mirror_status.txt" 2>/dev/null || true
    cp "$TOPO" "$EVID/seam_${tag}_ipc_topology.txt" 2>/dev/null || true

    # v8.38 read-only startup bootstrap: retain the generation that just rotated
    # out. FD 9 still points at the old immutable inode after the mirror's atomic
    # rename. We never write the live mirror, touch TCP/15332, parse H.264 here,
    # or signal/restart any CarPlay process.
    boot_tmp="${BOOT_PREV}.new.$$"
    if cat /proc/$$/fd/9 > "$boot_tmp" 2>/dev/null; then
      boot_bytes=$(wc -c < "$boot_tmp" 2>/dev/null || echo 0)
      if [ "$boot_bytes" -gt 0 ]; then
        mv "$boot_tmp" "$BOOT_PREV"
        boot_sha1=$(sha1_file "$BOOT_PREV")
        cat > "$BOOT_META.new" <<META
version=v8.38-read-only-bootstrap-snapshot
captured_epoch=$epoch
old_generation=$old_generation
new_generation=$new_generation
old_inode=$old_inode
bytes=$boot_bytes
sha1=${boot_sha1:-none}
source=previous-complete-mirror-generation
mirror_write=NEVER
h264_parse=IPHONE_ONLY
META
        mv "$BOOT_META.new" "$BOOT_META"
      else
        rm -f "$boot_tmp"
      fi
    else
      rm -f "$boot_tmp"
    fi

    echo "SEAM event=$event epoch=$epoch old_generation=$old_generation new_generation=$new_generation old_inode=$old_inode new_inode=$new_inode old_size=$old_size new_size=$new_size relay_pid=${rp:-none} relay_fd=$relay_fd relay_pos=$relay_pos relay_inode=$relay_inode relay_size=$relay_size relay_target=$relay_target old_tail256_sha1=${old_tail_sha1:-none} new_head256_sha1=${new_head_sha1:-none} old_sample_bytes=$old_sample_bytes new_sample_bytes=$new_sample_bytes old_sample_sha1=${old_sample_sha1:-none} new_sample_sha1=${new_sample_sha1:-none} sample_bytes=$SAMPLE_BYTES capture_complete=$([ "$old_sample_bytes" -gt 0 ] && [ "$new_sample_bytes" -gt 0 ] && echo YES || echo NO)" >> "$LOG"

    # Deterministic retention: keep the newest MAX_EVENTS complete seam groups.
    old_event=$((event-MAX_EVENTS))
    if [ "$old_event" -gt 0 ]; then
      old_tag=$(printf '%04d' "$old_event")
      rm -f "$EVID/seam_${old_tag}_"* 2>/dev/null || true
    fi

    exec 9<&-
    exec 9<"$LIVE" || exit 0
    old_inode=$new_inode
    old_generation=$new_generation
    snapshot_topology
  fi
  sleep 1
done
