#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
log(){ echo "[U2W-v8.27-rollback] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 91; fi
for f in u2w_mainvideo_relay_v823 u2wvideo-relay-start-v823.cgi u2wvideo-relay-status-v823.cgi; do
  [ -f "$P/$f" ] || { log "ABORT rollback payload missing $f"; exit 94; }
done
if [ -f /tmp/u2w_mainvideo_relay.pid ]; then p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true; fi
killall u2w_mainvideo_relay 2>/dev/null || true
rm -f /tmp/u2w_mainvideo_relay.pid /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new /tmp/u2w_mainvideo_validated_gop.cache
mkdir -p "$LIB" || exit 95
cp "$P/u2w_mainvideo_relay_v823" "$LIB/u2w_mainvideo_relay" || exit 96
cp "$P/u2wvideo-relay-start-v823.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 97
cp "$P/u2wvideo-relay-status-v823.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 98
chmod 755 "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 99
rm -f /etc/u2w_v8_27_live_edge_idr.marker /etc/u2w_v8_26_persistent_gop_bridge.marker /etc/u2w_v8_25_validated_gop_relay.marker /etc/u2w_v8_24_recent_idr_relay.marker
cat > /etc/u2w_v8_23_live_idr_relay.marker <<MARKER
U2W Dedicated MainVideo H264 Relay v8.23 restored by v8.27 safe rollback
software_version=$VER
product_type=$TYPE
base_mainvideo=v8.11
MARKER
: > /tmp/u2w_mainvideo_relay.log
"$LIB/u2w_mainvideo_relay" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
pid=$!; echo "$pid" > /tmp/u2w_mainvideo_relay.pid
sync
log 'safe rollback complete: v8.23 live-IDR relay restored; v8.11 AppleCarPlay capture untouched'
rm -f "$P/u2w_mainvideo_relay_v823" "$P/u2wvideo-relay-start-v823.cgi" "$P/u2wvideo-relay-status-v823.cgi" "$P/once.sh"
exit 0
