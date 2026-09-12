#!/bin/sh
set -u
P=/tmp/update/tmp
HUDDIR=/usr/lib/u2whud
RGDDIR=/usr/lib/u2wrgd
[ -x "$HUDDIR/u2whud_stop.sh" ] && "$HUDDIR/u2whud_stop.sh" >/dev/null 2>&1 || true
mkdir -p "$HUDDIR" "$RGDDIR" || exit 61
# Restore the exact pre-v8.15 components bundled from the working stack:
# Route v8.8 shim, MainVideo v8.11 stream CGI, HUD relay v8.14.3.
cp "$P/libu2w_rgd_preload_v88.so" "$RGDDIR/libu2w_rgd_preload.so" || exit 62
chmod 755 "$RGDDIR/libu2w_rgd_preload.so" || exit 63
cp "$P/u2wvideo-main-stream-v811.cgi" /etc/boa/cgi-bin/u2wvideo-main-stream.cgi || exit 64
chmod 755 /etc/boa/cgi-bin/u2wvideo-main-stream.cgi || exit 65
for f in u2whud_cast_relay u2whud_discovery u2whud_frame_ingress u2whud_test.jpg u2whud_stop.sh; do
  cp "$P/${f}_v8143" "$HUDDIR/$f" || exit 66
  chmod 755 "$HUDDIR/$f" || exit 67
done
for f in u2whud-start.cgi u2whud-stop.cgi u2whud-status.cgi; do
  cp "$P/${f}_v8143" "/etc/boa/cgi-bin/$f" || exit 68
  chmod 755 "/etc/boa/cgi-bin/$f" || exit 69
done
rm -f /etc/u2whud_bridge_v8_15.marker /etc/u2w_v8_15_reliability.marker
cat > /etc/u2whud_bridge_v8_14_3.marker <<'MARKER'
U2W HUD Live Frame Relay v8.14.3 restored by v8.15 uninstaller
MARKER
rm -f /tmp/u2whud_session_id /tmp/u2whud_session_discovery /tmp/u2whud_session_client \
      /tmp/u2whud_session_established /tmp/u2whud_session_fallback /tmp/u2whud_session_live
sync
rm -f "$P/once.sh"
exit 0
