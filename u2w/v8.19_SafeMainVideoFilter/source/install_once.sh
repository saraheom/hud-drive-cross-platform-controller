#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
BASEMARK=/etc/u2w_v8_17_latest_frame.marker
MARK=/etc/u2w_v8_19_safe_mainvideo_filter.marker
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
log(){ echo "[U2W-v8.19] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 201; fi
[ -f "$BASEMARK" ] || { log 'ABORT v8.17 LatestFrame base marker missing'; exit 202; }
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo exporter marker missing'; exit 203; }
[ -f "$P/u2w_mainvideo_streamer" ] || { log 'ABORT safe streamer payload missing'; exit 204; }
# Deliberately no AppleCarPlay/lib preload changes in this release.
cp "$P/u2w_mainvideo_streamer" "$DST" || exit 205
chmod 755 "$DST" || exit 206
cat > "$MARK" <<MARKER
U2W MainVideo Safe Filter v8.19
software_version=$VER
product_type=$TYPE
base_streamer=v8.17
mainvideo_exporter=v8.11-unchanged
applecarplay_hook_changes=none
filter=validated-800x480-sps-pps-slice
annexb_output=canonical-4byte-startcode
generation_identity=delivered_tail_fingerprint
MARKER
sync
log 'installed safe MainVideo CGI filter only; AppleCarPlay/exporter/route/media/HUD relay unchanged'
rm -f "$P/u2w_mainvideo_streamer" "$P/once.sh"
exit 0
