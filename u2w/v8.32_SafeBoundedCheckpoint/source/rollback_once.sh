#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
EXPECTED_V832_SHA1=b07824e46aee104157135af91ec7edb467c7afee
log(){ echo "[U2W-v8.32-rollback] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 221; fi
[ -f /etc/u2w_v8_32_safe_checkpoint.marker ] || { log 'ABORT v8.32 marker missing'; exit 222; }
OLD_SHA=$(sha1sum "$LIB/u2w_mainvideo_relay" 2>/dev/null | awk '{print $1}')
[ "$OLD_SHA" = "$EXPECTED_V832_SHA1" ] || { log "ABORT current relay is not exact v8.32 sha1=$OLD_SHA"; exit 223; }
for f in u2w_mainvideo_relay_v831 u2wvideo-relay-start-v831.cgi u2wvideo-relay-stop-v831.cgi u2wvideo-relay-status-v831.cgi; do [ -f "$P/$f" ] || exit 224; done
PF=/tmp/u2w_mainvideo_relay.pid
if [ -f "$PF" ]; then p=$(cat "$PF" 2>/dev/null || true); if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then exe=$(readlink "/proc/$p/exe" 2>/dev/null || true); [ "$exe" = "$LIB/u2w_mainvideo_relay" ] && kill "$p" 2>/dev/null || true; fi; fi
rm -f "$PF" /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new
cp "$P/u2w_mainvideo_relay_v831" "$LIB/u2w_mainvideo_relay" || exit 225
cp "$P/u2wvideo-relay-start-v831.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 226
cp "$P/u2wvideo-relay-stop-v831.cgi" /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi || exit 227
cp "$P/u2wvideo-relay-status-v831.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 228
chmod 755 "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 229
rm -f /etc/u2w_v8_32_safe_checkpoint.marker
cat > /etc/u2w_v8_31_navigation_priority_raw.marker <<MARKER
U2W MainVideo Navigation-Priority Raw Relay v8.31
software_version=$VER
product_type=$TYPE
base=v8.27.2_validated_safety_boundary
base_mainvideo=v8.11_exact
applecarplay_hook_changed=0
applecarplay_signal_policy=NEVER
applecarplay_restart_policy=NEVER
route_guidance_changed=0
now_playing_changed=0
hud_cast_relay_changed=0
relay_autostart=0
navigation_dependency=NONE
h264_tcp_port=15332
wire=U2WH2648_raw_v8_11_mirror_bytes
adapter_h264_parser=0
adapter_reference_chain=0
adapter_video_cache=0
raw_buffer_bytes=32768
client_policy=one_explicit_map_mode_client_then_exit
MARKER
sync
log 'rolled back to exact v8.31 raw relay; relay NOT started'
rm -f "$P/u2w_mainvideo_relay_v831" "$P/u2wvideo-relay-start-v831.cgi" "$P/u2wvideo-relay-stop-v831.cgi" "$P/u2wvideo-relay-status-v831.cgi" "$P/once.sh"
exit 0
