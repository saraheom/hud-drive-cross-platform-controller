#!/bin/sh
set -u
P=/tmp/update/tmp
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
MARK=/etc/u2w_v8_17_latest_frame.marker
log(){ echo "[U2W-v8.17-uninstall] $*" > /dev/console; }
[ -f "$P/u2w_mainvideo_streamer_v816" ] || { log 'ABORT v8.16 rollback streamer missing'; exit 97; }
cp "$P/u2w_mainvideo_streamer_v816" "$DST" || exit 98
chmod 755 "$DST" || exit 99
rm -f "$MARK"
sync
log 'restored v8.16 live-edge MainVideo streamer'
rm -f "$P/u2w_mainvideo_streamer_v816" "$P/once.sh"
exit 0
