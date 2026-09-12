#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
EXPECTED_SHA1=2c3eb90d018b29fb9f35ba807260fad0cfd0fe84
P=/tmp/update/tmp
HUDDIR=/usr/lib/u2whud
RGDDIR=/usr/lib/u2wrgd
RGDBAK=$RGDDIR/ARMiPhoneIAP2
RGDSHIM=$RGDDIR/libu2w_rgd_preload.so
VIDMARK=/etc/u2w_mainvideo_v8_11.marker
MARK=/etc/u2whud_bridge_v8_15.marker
HARDMARK=/etc/u2w_v8_15_reliability.marker
log(){ echo "[U2W-v8.15] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
if [ ! -f "$RGDBAK" ]; then log 'ABORT v8.8 Route Guidance backup missing'; exit 82; fi
BAKSHA=$(sha1sum "$RGDBAK" 2>/dev/null | awk '{print $1}')
[ "$BAKSHA" = "$EXPECTED_SHA1" ] || { log "ABORT saved original ARMiPhoneIAP2 mismatch=$BAKSHA"; exit 83; }
[ -f "$VIDMARK" ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 84; }

# Stop only the previous HUD relay daemons while replacing their executables.
[ -x "$HUDDIR/u2whud_stop.sh" ] && "$HUDDIR/u2whud_stop.sh" >/dev/null 2>&1 || true
mkdir -p "$HUDDIR" "$RGDDIR" || exit 85

# Harden Route Guidance / Now Playing snapshot publication.  The currently
# running ARMiPhoneIAP2 process keeps its mapped old shim until its next restart;
# a normal adapter power-cycle activates this copy.
cp "$P/libu2w_rgd_preload.so" "$RGDSHIM" || exit 86
chmod 755 "$RGDSHIM" || exit 87

# Replace only the v8.11 HTTP follower, not its proven AppleCarPlay exporter.
cp "$P/u2w_mainvideo_streamer" /etc/boa/cgi-bin/u2wvideo-main-stream.cgi || exit 88
chmod 755 /etc/boa/cgi-bin/u2wvideo-main-stream.cgi || exit 89

for f in u2whud_cast_relay u2whud_discovery u2whud_frame_ingress u2whud_test.jpg u2whud_stop.sh; do
  cp "$P/$f" "$HUDDIR/$f" || exit 90
  chmod 755 "$HUDDIR/$f" || exit 91
done
for f in u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do
  cp "$P/$f" "/etc/boa/cgi-bin/$f" || exit 92
  chmod 755 "/etc/boa/cgi-bin/$f" || exit 93
done
rm -f /etc/u2whud_bridge_v8_12.marker /etc/u2whud_bridge_v8_13.marker \
      /etc/u2whud_bridge_v8_14.marker /etc/u2whud_bridge_v8_14_1.marker \
      /etc/u2whud_bridge_v8_14_2.marker /etc/u2whud_bridge_v8_14_3.marker
rm -f /tmp/u2whud_session_id /tmp/u2whud_session_discovery /tmp/u2whud_session_client \
      /tmp/u2whud_session_established /tmp/u2whud_session_fallback /tmp/u2whud_session_live
cat > "$MARK" <<MARKER
U2W HUD Live Frame Relay v8.15
software_version=$VER
product_type=$TYPE
u2w_ap_unchanged=1
hud_network_role=station
cast_server_ip=192.168.50.2
udp_discovery_port=15320
mjpeg_port=15330
iphone_frame_ingress_port=15331
session_scoped_status=1
preserve_daemons_across_display_stop=1
MARKER
cat > "$HARDMARK" <<MARKER
U2W v8.15 reliability hardening
route_media_json_locked_atomic_publish=1
mainvideo_rotation_safe_streamer=1
route_shim_sha256=$(sha256sum "$RGDSHIM" 2>/dev/null | awk '{print $1}')
mainvideo_streamer_sha256=$(sha256sum /etc/boa/cgi-bin/u2wvideo-main-stream.cgi 2>/dev/null | awk '{print $1}')
MARKER
sync
log 'installed: rotation-safe MainVideo stream + locked route/media JSON + session-scoped HUD relay; power-cycle adapter to activate new Route Guidance shim'
for f in libu2w_rgd_preload.so u2w_mainvideo_streamer u2whud_cast_relay u2whud_discovery u2whud_frame_ingress u2whud_test.jpg u2whud_stop.sh u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do rm -f "$P/$f"; done
rm -f "$P/once.sh"
exit 0
