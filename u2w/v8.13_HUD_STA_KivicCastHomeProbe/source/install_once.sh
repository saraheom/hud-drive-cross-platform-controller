#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
DIR=/usr/lib/u2whud
MARK=/etc/u2whud_bridge_v8_13.marker
log(){ echo "[U2W-HUD-BRIDGE-v8.13] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
[ -x "$DIR/u2whud_stop.sh" ] && "$DIR/u2whud_stop.sh" >/dev/null 2>&1 || true
rm -f /etc/u2whud_bridge_v8_12.marker /etc/u2whud_bridge_v8_13.marker
rm -f /etc/boa/cgi-bin/u2whud-capability.cgi /etc/boa/cgi-bin/u2whud-start.cgi /etc/boa/cgi-bin/u2whud-stop.cgi /etc/boa/cgi-bin/u2whud-status.cgi
rm -rf "$DIR"
mkdir -p "$DIR" || exit 82
for f in u2whud_cast_test u2whud_test.jpg u2whud_stop.sh; do cp "$P/$f" "$DIR/$f" || exit 83; chmod 755 "$DIR/$f" || exit 84; done
for f in u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do cp "$P/$f" "/etc/boa/cgi-bin/$f" || exit 85; chmod 755 "/etc/boa/cgi-bin/$f" || exit 86; done
cat > "$MARK" <<MARKER
U2W HUD-as-STA KivicCast Home Probe v8.13
software_version=$VER
product_type=$TYPE
non_destructive=1
u2w_ap_unchanged=1
cast_server_ip=192.168.50.2
udp_discovery_port=15320
mjpeg_port=15330
hud_network_role=station
MARKER
sync
log 'installed; U2W AP unchanged; use u2whud-start.cgi to arm known-image cast server'
for f in u2whud_cast_test u2whud_test.jpg u2whud_stop.sh u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do rm -f "$P/$f"; done
rm -f "$P/once.sh"
exit 0
