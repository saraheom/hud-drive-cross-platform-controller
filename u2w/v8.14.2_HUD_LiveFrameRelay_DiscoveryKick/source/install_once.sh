#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
DIR=/usr/lib/u2whud
MARK=/etc/u2whud_bridge_v8_14_2.marker
log(){ echo "[U2W-HUD-RELAY-v8.14.2] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
[ -x "$DIR/u2whud_stop.sh" ] && "$DIR/u2whud_stop.sh" >/dev/null 2>&1 || true
rm -f /etc/u2whud_bridge_v8_12.marker /etc/u2whud_bridge_v8_13.marker /etc/u2whud_bridge_v8_14.marker /etc/u2whud_bridge_v8_14_1.marker /etc/u2whud_bridge_v8_14_2.marker
rm -f /etc/boa/cgi-bin/u2whud-capability.cgi /etc/boa/cgi-bin/u2whud-start.cgi /etc/boa/cgi-bin/u2whud-stop.cgi /etc/boa/cgi-bin/u2whud-status.cgi
rm -rf "$DIR"; mkdir -p "$DIR" || exit 82
for f in u2whud_cast_relay u2whud_discovery u2whud_frame_ingress u2whud_test.jpg u2whud_stop.sh; do cp "$P/$f" "$DIR/$f" || exit 83; chmod 755 "$DIR/$f" || exit 84; done
for f in u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do cp "$P/$f" "/etc/boa/cgi-bin/$f" || exit 85; chmod 755 "/etc/boa/cgi-bin/$f" || exit 86; done
cat > "$MARK" <<MARKER
U2W HUD Live Frame Relay v8.14.2
software_version=$VER
product_type=$TYPE
u2w_ap_unchanged=1
hud_network_role=station
cast_server_ip=192.168.50.2
udp_discovery_port=15320
persistent_discovery=1
mjpeg_port=15330
iphone_frame_ingress_port=15331
preserves_v8_8_route_exporter=1
preserves_v8_11_mainvideo_exporter=1
MARKER
sync
log 'installed; idempotent persistent discovery + live frame relay available via u2whud-start.cgi'
for f in u2whud_cast_relay u2whud_discovery u2whud_frame_ingress u2whud_test.jpg u2whud_stop.sh u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do rm -f "$P/$f"; done
rm -f "$P/once.sh"; exit 0
