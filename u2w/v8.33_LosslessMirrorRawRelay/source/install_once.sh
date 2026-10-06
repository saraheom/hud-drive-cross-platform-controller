#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
SHIM=$LIB/libu2w_mainvideo_live.so
MARK=/etc/u2w_v8_33_lossless_mirror.marker
V811_SHIM_SHA1=7ab8e227893277c9c1135a398e24e41c8f84d4df
V833_SHIM_SHA1=67ec2d1d69a50096c0b14e26048fd7b2a00bde08
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
V832_RELAY_SHA1=b07824e46aee104157135af91ec7edb467c7afee
log(){ echo "[U2W-v8.33] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 221; fi
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 222; }
[ -f /etc/u2w_v8_27_2_passive_codec.marker ] || { log 'ABORT validated v8.27.2 passive-codec marker missing'; exit 223; }
[ -f /etc/u2whud_bridge_v8_15_1.marker ] || { log 'ABORT v8.15.1 HUD relay marker missing'; exit 224; }
for f in libu2w_mainvideo_live.so u2w_mainvideo_relay u2wvideo-relay-start.cgi u2wvideo-relay-stop.cgi u2wvideo-relay-status.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 225; }; done
CUR_SHIM=$(sha1sum "$SHIM" 2>/dev/null | awk '{print $1}')
if [ "$CUR_SHIM" != "$V811_SHIM_SHA1" ] && [ "$CUR_SHIM" != "$V833_SHIM_SHA1" ]; then log "ABORT unexpected MainVideo shim sha1=$CUR_SHIM"; exit 226; fi
CUR_RELAY=$(sha1sum "$LIB/u2w_mainvideo_relay" 2>/dev/null | awk '{print $1}')
if [ "$CUR_RELAY" != "$V832_RELAY_SHA1" ] && [ "$CUR_RELAY" != "$V831_RELAY_SHA1" ]; then log "ABORT unexpected relay sha1=$CUR_RELAY"; exit 227; fi
# Stop ONLY our standalone TCP relay. Do not signal/restart AppleCarPlay or ARMiPhoneIAP2.
PF=/tmp/u2w_mainvideo_relay.pid
if [ -f "$PF" ]; then
  p=$(cat "$PF" 2>/dev/null || true)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    exe=$(readlink "/proc/$p/exe" 2>/dev/null || true)
    [ "$exe" = "$LIB/u2w_mainvideo_relay" ] && kill "$p" 2>/dev/null || true
  fi
fi
rm -f "$PF" /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new /tmp/u2w_mainvideo_live.next
# Replace only the passive mirror shim and standalone relay. The updater's normal reboot
# will load the new shim into AppleCarPlay; this script itself never signals that process.
cp "$P/libu2w_mainvideo_live.so" "$SHIM" || exit 228
cp "$P/u2w_mainvideo_relay" "$LIB/u2w_mainvideo_relay" || exit 229
cp "$P/u2wvideo-relay-start.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 230
cp "$P/u2wvideo-relay-stop.cgi" /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi || exit 231
cp "$P/u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 232
chmod 755 "$SHIM" "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 233
# Preserve post-v8.30 safety boundary: no MainVideo boot helper/autostart.
rm -f /etc/init.d/S99u2w_mainvideo_v830 /etc/rcS.d/S99u2w_mainvideo_v830 "$LIB/u2w_mainvideo_v830_boot.sh"
cat > "$MARK" <<MARKER
U2W MainVideo Lossless Mirror + v8.31 Raw Relay v8.33
software_version=$VER
product_type=$TYPE
previous_shim_sha1=$CUR_SHIM
active_shim_sha1=$V833_SHIM_SHA1
raw_relay_sha1=$V831_RELAY_SHA1
applecarplay_real_write_order=REAL_WRITE_FIRST
applecarplay_payload_modified=0
applecarplay_signal_policy=NEVER
applecarplay_restart_policy=NEVER
source_selection=UNCHANGED_V8_11_FIRST_SPS_FD
mirror_rotation=ATOMIC_FULL_SUCCESSFUL_WRITE_INODE_SWAP
mirror_partial_write_policy=WRITE_ALL
vectored_write_policy=MIRROR_ONLY_REAL_RETURN_BYTES
relay_architecture=V8_31_RAW_32K
relay_autostart=0
adapter_h264_parser=0
adapter_video_cache=0
route_guidance_changed=0
now_playing_changed=0
hud_cast_relay_changed=0
MARKER
rm -f /etc/u2w_v8_32_safe_checkpoint.marker /etc/u2w_v8_31_navigation_priority_raw.marker /etc/u2w_v8_30_reference_chain.marker /etc/u2w_v8_29_incremental_source.marker /etc/u2w_v8_28_safe_fd_reacquire.marker
sync
log 'installed v8.33 lossless passive mirror + exact v8.31 raw relay; normal updater reboot required; AppleCarPlay not signaled'
rm -f "$P/libu2w_mainvideo_live.so" "$P/u2w_mainvideo_relay" "$P/u2wvideo-relay-start.cgi" "$P/u2wvideo-relay-stop.cgi" "$P/u2wvideo-relay-status.cgi" "$P/once.sh"
exit 0
