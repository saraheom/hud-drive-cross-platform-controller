#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
DIR=/usr/lib/u2wvideo
log(){ echo "[U2W-MAINVIDEO-v8.18-UNINSTALL] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 191; fi
cp "$P/libu2w_mainvideo_live_v811.so" "$DIR/libu2w_mainvideo_live.so" || exit 192
chmod 755 "$DIR/libu2w_mainvideo_live.so" || exit 193
cp "$P/u2wvideo-status-v811.cgi" /etc/boa/cgi-bin/u2wvideo-status.cgi || exit 194
chmod 755 /etc/boa/cgi-bin/u2wvideo-status.cgi || exit 195
rm -f /etc/u2w_v8_18_fd_reselect.marker
rm -f /tmp/u2w_mainvideo_live.h264 /tmp/u2w_mainvideo_status.txt /tmp/u2w_mainvideo_status.txt.tmp
sync
log 'restored exact v8.11 MainVideo shim/status; v8.17 streamer remains installed; FULL POWER CYCLE required'
rm -f "$P/libu2w_mainvideo_live_v811.so" "$P/u2wvideo-status-v811.cgi" "$P/once.sh"
exit 0
