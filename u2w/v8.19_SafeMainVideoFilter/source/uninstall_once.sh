#!/bin/sh
set -u
P=/tmp/update/tmp
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
MARK=/etc/u2w_v8_19_safe_mainvideo_filter.marker
log(){ echo "[U2W-v8.19-uninstall] $*" > /dev/console; }
[ -f "$P/u2w_mainvideo_streamer_v817" ] || { log 'ABORT v8.17 rollback streamer missing'; exit 207; }
cp "$P/u2w_mainvideo_streamer_v817" "$DST" || exit 208
chmod 755 "$DST" || exit 209
rm -f "$MARK"
sync
log 'restored exact v8.17 LatestFrame CGI streamer; v8.11 exporter untouched'
rm -f "$P/u2w_mainvideo_streamer_v817" "$P/once.sh"
exit 0
