#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
BASEMARK=/etc/u2w_v8_15_reliability.marker
PRIMERMARK=/etc/u2whud_bridge_v8_15_1.marker
MARK=/etc/u2w_v8_16_live_edge.marker
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
log(){ echo "[U2W-v8.16] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 81; fi
[ -f "$BASEMARK" ] || { log 'ABORT v8.15 Reliability base marker missing'; exit 82; }
[ -f "$PRIMERMARK" ] || { log 'ABORT v8.15.1 primer marker missing'; exit 83; }
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 84; }
[ -f "$P/u2w_mainvideo_streamer" ] || { log 'ABORT streamer payload missing'; exit 85; }
cp "$P/u2w_mainvideo_streamer" "$DST" || exit 86
chmod 755 "$DST" || exit 87
cat > "$MARK" <<MARKER
U2W MainVideo Live-Edge Streamer v8.16
software_version=$VER
product_type=$TYPE
base=v8.15.1
initial_bootstrap=newest_sps_pps_idr
reopen_path_at_eof=1
generation_rollover_bootstrap=newest_gop
byte_zero_replay_on_reconnect=0
MARKER
sync
log 'installed live-edge MainVideo streamer; relay/route/media unchanged'
rm -f "$P/u2w_mainvideo_streamer" "$P/once.sh"
exit 0
