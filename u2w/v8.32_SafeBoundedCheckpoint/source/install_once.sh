#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
MARK=/etc/u2w_v8_32_safe_checkpoint.marker
EXPECTED_SELECTOR_SHA1=7ab8e227893277c9c1135a398e24e41c8f84d4df
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
log(){ echo "[U2W-v8.32] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 201; fi
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 202; }
[ -f /etc/u2w_v8_27_2_passive_codec.marker ] || { log 'ABORT validated v8.27.2 passive-codec marker missing'; exit 203; }
[ -f /etc/u2whud_bridge_v8_15_1.marker ] || { log 'ABORT v8.15.1 HUD relay marker missing'; exit 204; }
for f in u2w_mainvideo_relay u2wvideo-relay-start.cgi u2wvideo-relay-stop.cgi u2wvideo-relay-status.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 205; }; done
SEL_SHA=$(sha1sum "$LIB/libu2w_mainvideo_live.so" 2>/dev/null | awk '{print $1}')
[ "$SEL_SHA" = "$EXPECTED_SELECTOR_SHA1" ] || { log "ABORT selector not exact validated v8.11 sha1=$SEL_SHA"; exit 206; }
OLD_SHA=$(sha1sum "$LIB/u2w_mainvideo_relay" 2>/dev/null | awk '{print $1}')
[ "$OLD_SHA" = "$V831_RELAY_SHA1" ] || { log "ABORT expected current v8.31 relay sha1=$OLD_SHA"; exit 207; }

# Stop ONLY the standalone MainVideo relay. Never signal/restart/inject AppleCarPlay,
# ARMiPhoneIAP2, Route Guidance, or Now Playing.
PF=/tmp/u2w_mainvideo_relay.pid
if [ -f "$PF" ]; then
  p=$(cat "$PF" 2>/dev/null || true)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    exe=$(readlink "/proc/$p/exe" 2>/dev/null || true)
    [ "$exe" = "$LIB/u2w_mainvideo_relay" ] && kill "$p" 2>/dev/null || true
  fi
fi
rm -f "$PF" /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new

# Explicitly keep the post-v8.30 safety boundary: no MainVideo boot helper/autostart.
rm -f /etc/init.d/S99u2w_mainvideo_v830 /etc/rcS.d/S99u2w_mainvideo_v830 "$LIB/u2w_mainvideo_v830_boot.sh"
mkdir -p "$LIB" || exit 208
cp "$P/u2w_mainvideo_relay" "$LIB/u2w_mainvideo_relay" || exit 209
cp "$P/u2wvideo-relay-start.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 210
cp "$P/u2wvideo-relay-stop.cgi" /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi || exit 211
cp "$P/u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 212
chmod 755 "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 213
cat > "$MARK" <<MARKER
U2W MainVideo Safe Bounded Checkpoint Relay v8.32
software_version=$VER
product_type=$TYPE
base=v8.31_navigation_priority_safety_boundary
base_mainvideo=v8.11_exact
base_selector_sha1=$SEL_SHA
applecarplay_hook_changed=0
applecarplay_signal_policy=NEVER
applecarplay_restart_policy=NEVER
source_selector_changed=0
route_guidance_changed=0
now_playing_changed=0
hud_cast_relay_changed=0
relay_autostart=0
navigation_dependency=NONE
h264_tcp_port=15332
wire=U2WH2649_length_framed_validated_nal
adapter_h264_parser=validator_only
adapter_checkpoint_cap_bytes=1572864
historical_generation_scan=0
current_mirror_startup_forward_scan=1
source_reacquire=NEVER
client_policy=one_explicit_map_mode_client
MARKER
rm -f /etc/u2w_v8_31_navigation_priority_raw.marker /etc/u2w_v8_30_reference_chain.marker /etc/u2w_v8_29_incremental_source.marker /etc/u2w_v8_28_safe_fd_reacquire.marker
sync
log 'installed v8.32 safe bounded checkpoint relay; relay NOT started; v8.11 exporter + Route Guidance untouched'
rm -f "$P/u2w_mainvideo_relay" "$P/u2wvideo-relay-start.cgi" "$P/u2wvideo-relay-stop.cgi" "$P/u2wvideo-relay-status.cgi" "$P/once.sh"
exit 0
