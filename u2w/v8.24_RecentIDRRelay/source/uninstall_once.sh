#!/bin/sh
set -u
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
HUDDIR=/usr/lib/u2whud
if [ -f /tmp/u2w_mainvideo_relay.pid ]; then
  p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
if [ -f /tmp/u2whud_cast.pid ]; then
  p=$(cat /tmp/u2whud_cast.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
rm -f /tmp/u2w_mainvideo_relay.pid /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new /tmp/u2whud_cast.pid /tmp/u2whud_session_established
cp "$P/u2w_mainvideo_relay_v823" "$LIB/u2w_mainvideo_relay"
cp "$P/u2wvideo-relay-start-v823.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi
cp "$P/u2wvideo-relay-status-v823.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi
cp "$P/u2whud_cast_relay_v8151" "$HUDDIR/u2whud_cast_relay"
chmod 755 "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi "$HUDDIR/u2whud_cast_relay"
rm -f /etc/u2w_v8_24_recent_idr_relay.marker
cat > /etc/u2w_v8_23_live_idr_relay.marker <<MARKER
U2W MainVideo Live-IDR Relay v8.23 restored by v8.24 uninstall
MARKER
: > /tmp/u2w_mainvideo_relay.log
"$LIB/u2w_mainvideo_relay" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
echo $! > /tmp/u2w_mainvideo_relay.pid
sync
rm -f "$P/u2w_mainvideo_relay_v823" "$P/u2wvideo-relay-start-v823.cgi" "$P/u2wvideo-relay-status-v823.cgi" "$P/u2whud_cast_relay_v8151" "$P/once.sh"
exit 0
