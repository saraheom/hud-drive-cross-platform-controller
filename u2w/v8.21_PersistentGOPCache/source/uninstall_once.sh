#!/bin/sh
set -u
P=/tmp/update/tmp
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
if [ -f /tmp/u2w_mainvideo_cache.pid ]; then
  p=$(cat /tmp/u2w_mainvideo_cache.pid 2>/dev/null || true)
  [ -n "$p" ] && kill "$p" 2>/dev/null || true
fi
[ -f "$P/u2w_mainvideo_streamer_v820" ] || exit 91
cp "$P/u2w_mainvideo_streamer_v820" "$DST" || exit 92
chmod 755 "$DST" || exit 93
rm -f /etc/boa/cgi-bin/u2wvideo-cache-start.cgi /etc/boa/cgi-bin/u2wvideo-cache-status.cgi
rm -f /usr/lib/u2wvideo/u2w_mainvideo_cache
rm -f /tmp/u2w_mainvideo_cache.pid /tmp/u2w_mainvideo_cache_ready /tmp/u2w_mainvideo_gop_cache.h264 /tmp/u2w_mainvideo_cache.log
rm -f /etc/u2w_v8_21_gop_cache.marker
sync
rm -f "$P/u2w_mainvideo_streamer_v820" "$P/once.sh"
exit 0
