#!/bin/sh
set -u
P=/tmp/update/tmp
HUDDIR=/usr/lib/u2whud
if [ -f /tmp/u2w_mainvideo_relay.pid ]; then
  p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
[ -f "$P/u2whud_cast_relay_v8151" ] || exit 91
if [ -f /tmp/u2whud_cast.pid ]; then
  p=$(cat /tmp/u2whud_cast.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
rm -f /tmp/u2whud_cast.pid /tmp/u2whud_session_established
cp "$P/u2whud_cast_relay_v8151" "$HUDDIR/u2whud_cast_relay" || exit 92
chmod 755 "$HUDDIR/u2whud_cast_relay" || exit 93
rm -f /usr/lib/u2wvideo/u2w_mainvideo_relay /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi
rm -f /tmp/u2w_mainvideo_relay.pid /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new /tmp/u2w_mainvideo_relay.log
rm -f /etc/u2w_v8_22_h264_relay.marker
# Return the adapter to the pre-v8.22 v8.21 video state when that helper exists.
if [ -x /etc/boa/cgi-bin/u2wvideo-cache-start.cgi ]; then
  /etc/boa/cgi-bin/u2wvideo-cache-start.cgi >/dev/null 2>&1 || true
fi
sync
rm -f "$P/u2whud_cast_relay_v8151" "$P/once.sh"
exit 0
