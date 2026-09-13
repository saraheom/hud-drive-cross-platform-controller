#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
log(){ echo "[U2W-v8.16-uninstall] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
[ -f /etc/u2w_v8_15_reliability.marker ] || { log 'ABORT v8.15 base marker missing'; exit 82; }
[ -f "$P/u2w_mainvideo_streamer_v815" ] || { log 'ABORT v8.15 streamer payload missing'; exit 83; }
cp "$P/u2w_mainvideo_streamer_v815" "$DST" || exit 84
chmod 755 "$DST" || exit 85
rm -f /etc/u2w_v8_16_live_edge.marker
sync
log 'restored v8.15 rotation-safe streamer'
rm -f "$P/u2w_mainvideo_streamer_v815" "$P/once.sh"
exit 0
