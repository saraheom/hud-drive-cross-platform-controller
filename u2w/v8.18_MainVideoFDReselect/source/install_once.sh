#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
DIR=/usr/lib/u2wvideo
SHIM=$DIR/libu2w_mainvideo_live.so
OLD_SHA1=7ab8e227893277c9c1135a398e24e41c8f84d4df
NEW_SHA1=4ab551a525055cc47964e3dda28eec3273d91793
P=/tmp/update/tmp
MARK=/etc/u2w_v8_18_fd_reselect.marker
log(){ echo "[U2W-MAINVIDEO-v8.18] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 181; fi
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo base marker missing'; exit 182; }
[ -f /etc/u2w_v8_17_latest_frame.marker ] || { log 'ABORT v8.17 LatestFrame marker missing'; exit 183; }
[ -f "$SHIM" ] || { log 'ABORT active MainVideo shim missing'; exit 184; }
CUR=$(sha1sum "$SHIM" 2>/dev/null | awk '{print $1}')
if [ "$CUR" != "$OLD_SHA1" ] && [ "$CUR" != "$NEW_SHA1" ]; then log "ABORT unexpected MainVideo shim sha1=$CUR"; exit 185; fi
cp "$P/libu2w_mainvideo_live.so" "$SHIM" || exit 186
chmod 755 "$SHIM" || exit 187
cp "$P/u2wvideo-status-v818.cgi" /etc/boa/cgi-bin/u2wvideo-status.cgi || exit 188
chmod 755 /etc/boa/cgi-bin/u2wvideo-status.cgi || exit 189
rm -f /tmp/u2w_mainvideo_live.h264 /tmp/u2w_mainvideo_status.txt /tmp/u2w_mainvideo_status.txt.tmp
cat > "$MARK" <<MARKER
U2W MainVideo fd-reselection v8.18
software_version=$VER
product_type=$TYPE
previous_shim_sha1=$OLD_SHA1
active_shim_sha1=$NEW_SHA1
requires_v8_17_latest_frame=1
passive_only=1
fd_close_hook=1
validated_sps_pps_idr_reselection=1
content_watchdog=1
MARKER
sync
log 'installed v8.18 fd-reselection shim; FULL POWER CYCLE required to load it into AppleCarPlay'
rm -f "$P/libu2w_mainvideo_live.so" "$P/u2wvideo-status-v818.cgi" "$P/once.sh"
exit 0
