#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
HUDDIR=/usr/lib/u2whud
log(){ echo "[U2W-v8.15.1-uninstall] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
[ -f /etc/u2w_v8_15_reliability.marker ] || { log 'ABORT v8.15 base marker missing'; exit 82; }
[ -x "$HUDDIR/u2whud_stop.sh" ] && "$HUDDIR/u2whud_stop.sh" >/dev/null 2>&1 || true
cp "$P/u2whud_cast_relay_v815" "$HUDDIR/u2whud_cast_relay" || exit 83
chmod 755 "$HUDDIR/u2whud_cast_relay" || exit 84
for f in u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do
  cp "$P/${f}_v815" "/etc/boa/cgi-bin/$f" || exit 85
  chmod 755 "/etc/boa/cgi-bin/$f" || exit 86
done
rm -f /etc/u2whud_bridge_v8_15_1.marker
rm -f /tmp/u2whud_session_discovery /tmp/u2whud_session_client \
      /tmp/u2whud_session_established /tmp/u2whud_session_fallback /tmp/u2whud_session_live
sync
log 'restored v8.15 HUD cast relay/CGIs'
for f in u2whud_cast_relay_v815 u2whud-start.cgi_v815 u2whud-stop.cgi_v815 u2whud-status.cgi_v815; do rm -f "$P/$f"; done
rm -f "$P/once.sh"
exit 0
