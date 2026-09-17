#!/bin/sh
set -u
P=/tmp/update/tmp
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
MARK=/etc/u2w_v8_20_validated_gop.marker
log(){ echo "[U2W-v8.20-uninstall] $*" > /dev/console; }
[ -f "$P/u2w_mainvideo_streamer_v817" ] || { log 'ABORT v8.17 rollback streamer missing'; exit 97; }
cp "$P/u2w_mainvideo_streamer_v817" "$DST" || exit 98
chmod 755 "$DST" || exit 99
rm -f "$MARK"
sync
log 'restored v8.17 live-edge MainVideo streamer'
rm -f "$P/u2w_mainvideo_streamer_v817" "$P/once.sh"
exit 0
