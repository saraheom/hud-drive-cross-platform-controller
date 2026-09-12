#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
HUDDIR=/usr/lib/u2whud
BASEMARK=/etc/u2w_v8_15_reliability.marker
MARK=/etc/u2whud_bridge_v8_15_1.marker
log(){ echo "[U2W-v8.15.1] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
[ -f "$BASEMARK" ] || { log 'ABORT v8.15 Reliability base marker missing'; exit 82; }
[ -f "$P/u2whud_cast_relay" ] || { log 'ABORT cast relay payload missing'; exit 83; }

# Stop the current HUD relay daemons before replacing the cast executable/CGIs.
[ -x "$HUDDIR/u2whud_stop.sh" ] && "$HUDDIR/u2whud_stop.sh" >/dev/null 2>&1 || true
mkdir -p "$HUDDIR" || exit 84
cp "$P/u2whud_cast_relay" "$HUDDIR/u2whud_cast_relay" || exit 85
chmod 755 "$HUDDIR/u2whud_cast_relay" || exit 86
for f in u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do
  cp "$P/$f" "/etc/boa/cgi-bin/$f" || exit 87
  chmod 755 "/etc/boa/cgi-bin/$f" || exit 88
done
rm -f /tmp/u2whud_session_discovery /tmp/u2whud_session_client \
      /tmp/u2whud_session_established /tmp/u2whud_session_fallback /tmp/u2whud_session_live
cat > "$MARK" <<MARKER
U2W HUD Live Frame Relay v8.15.1
software_version=$VER
product_type=$TYPE
base=v8.15
known_image_primer=0
live_frame_primer=1
hold_last_frame_when_live_input_unavailable=1
MARKER
sync
log 'installed: no known-image primer; first valid live iPhone frame primes HUD decoder'
for f in u2whud_cast_relay u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do rm -f "$P/$f"; done
rm -f "$P/once.sh"
exit 0
