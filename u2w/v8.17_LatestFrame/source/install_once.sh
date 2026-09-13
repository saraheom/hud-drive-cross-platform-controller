#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
BASEMARK=/etc/u2w_v8_16_live_edge.marker
MARK=/etc/u2w_v8_17_latest_frame.marker
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
log(){ echo "[U2W-v8.17] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 91; fi
[ -f "$BASEMARK" ] || { log 'ABORT v8.16 LiveEdge base marker missing'; exit 92; }
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 93; }
[ -f "$P/u2w_mainvideo_streamer" ] || { log 'ABORT streamer payload missing'; exit 94; }
cp "$P/u2w_mainvideo_streamer" "$DST" || exit 95
chmod 755 "$DST" || exit 96
cat > "$MARK" <<MARKER
U2W MainVideo Latest-Frame Streamer v8.17
software_version=$VER
product_type=$TYPE
base=v8.16
initial_bootstrap=newest_sps_pps_idr
reopen_path_at_eof=1
generation_identity=delivered_tail_fingerprint
generation_mismatch_bootstrap=newest_gop
historical_offset_reuse=0
MARKER
sync
log 'installed latest-frame generation-guard MainVideo streamer; relay/route/media unchanged'
rm -f "$P/u2w_mainvideo_streamer" "$P/once.sh"
exit 0
