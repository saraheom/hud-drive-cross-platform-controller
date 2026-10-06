#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
MARK=/etc/u2w_v8_25_validated_gop_relay.marker
log(){ echo "[U2W-v8.25] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 91; fi
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 92; }
[ -f /etc/u2whud_bridge_v8_15_1.marker ] || { log 'ABORT v8.15.1 HUD relay marker missing'; exit 93; }
for f in u2w_mainvideo_relay u2wvideo-relay-start.cgi u2wvideo-relay-status.cgi; do
  [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 94; }
done
if [ -f /tmp/u2w_mainvideo_relay.pid ]; then
  p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
killall u2w_mainvideo_relay 2>/dev/null || true
killall u2w_mainvideo_streamer 2>/dev/null || true
killall u2w_mainvideo_cache 2>/dev/null || true
rm -f /tmp/u2w_mainvideo_relay.pid /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new
mkdir -p "$LIB" || exit 95
cp "$P/u2w_mainvideo_relay" "$LIB/u2w_mainvideo_relay" || exit 96
cp "$P/u2wvideo-relay-start.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 97
cp "$P/u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 98
chmod 755 "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 99
cat > "$MARK" <<MARKER
U2W MainVideo Validated-GOP Recovery Relay v8.25
software_version=$VER
product_type=$TYPE
base_mainvideo=v8.11
applecarplay_hook_changed=0
route_guidance_changed=0
now_playing_changed=0
hud_cast_relay_changed=0
long_lived_boa_video=0
h264_tcp_port=15332
wire=U2WH2643_length_framed_nal
bootstrap=newest_validated_file_gop_or_next_live_idr
file_gop_catchup_cap_bytes=50331648
MARKER
rm -f /etc/u2w_v8_24_recent_idr_relay.marker /etc/u2w_v8_23_live_idr_relay.marker /etc/u2w_v8_22_h264_relay.marker
: > /tmp/u2w_mainvideo_relay.log
"$LIB/u2w_mainvideo_relay" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
pid=$!; echo "$pid" > /tmp/u2w_mainvideo_relay.pid
sync
log 'installed validated-GOP recovery relay; AppleCarPlay/route/media/HUD cast untouched'
rm -f "$P/u2w_mainvideo_relay" "$P/u2wvideo-relay-start.cgi" "$P/u2wvideo-relay-status.cgi" "$P/once.sh"
exit 0
