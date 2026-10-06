#!/bin/sh
set -u
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
if [ -f /tmp/u2w_mainvideo_relay.pid ]; then
  p=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null || true); [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
killall u2w_mainvideo_relay 2>/dev/null || true
rm -f /tmp/u2w_mainvideo_relay.pid /tmp/u2w_h264_relay_status.txt /tmp/u2w_h264_relay_status.new
cp "$P/u2w_mainvideo_relay_v824" "$LIB/u2w_mainvideo_relay" || exit 96
cp "$P/u2wvideo-relay-start-v824.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 97
cp "$P/u2wvideo-relay-status-v824.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 98
chmod 755 "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 99
rm -f /etc/u2w_v8_25_validated_gop_relay.marker
cat > /etc/u2w_v8_24_recent_idr_relay.marker <<MARKER
U2W MainVideo Recent-IDR Relay v8.24 source-revision rollback from v8.25
MARKER
: > /tmp/u2w_mainvideo_relay.log
"$LIB/u2w_mainvideo_relay" >>/tmp/u2w_mainvideo_relay.log 2>&1 &
echo $! > /tmp/u2w_mainvideo_relay.pid
sync
rm -f "$P/u2w_mainvideo_relay_v824" "$P/u2wvideo-relay-start-v824.cgi" "$P/u2wvideo-relay-status-v824.cgi" "$P/once.sh"
exit 0
