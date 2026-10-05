#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
MARK=/etc/u2w_v8_36_seam_observer.marker
MIRROR=/usr/lib/u2wvideo/libu2w_mainvideo_live.so
RELAY=/usr/lib/u2wvideo/u2w_mainvideo_relay
V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
log(){ echo "[U2W-v8.36] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 221; fi
[ -f /etc/u2w_v8_35_bounded_keyframe.marker ] || { log 'ABORT v8.35 marker missing'; exit 222; }
[ -f /etc/u2w_v8_34_hard_bounded_mirror.marker ] || { log 'ABORT v8.34 mirror marker missing'; exit 223; }
[ "$(sha1sum "$MIRROR" 2>/dev/null | awk '{print $1}')" = "$V834_SHIM_SHA1" ] || { log 'ABORT v8.34 mirror bytes not exact'; exit 224; }
[ "$(sha1sum "$RELAY" 2>/dev/null | awk '{print $1}')" = "$V831_RELAY_SHA1" ] || { log 'ABORT v8.31 relay bytes not exact'; exit 225; }
for f in u2w_generation_seam_observer.sh u2wvideo-relay-start.cgi u2wvideo-relay-status.cgi u2wvideo-seam-log.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 226; }; done
# Install diagnostics only. Never replace MIRROR or RELAY and never signal CarPlay processes.
cp "$P/u2w_generation_seam_observer.sh" /usr/bin/u2w_generation_seam_observer.sh || exit 227
cp "$P/u2wvideo-relay-start.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 228
cp "$P/u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 229
cp "$P/u2wvideo-seam-log.cgi" /etc/boa/cgi-bin/u2wvideo-seam-log.cgi || exit 230
chmod 755 /usr/bin/u2w_generation_seam_observer.sh /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi /etc/boa/cgi-bin/u2wvideo-seam-log.cgi || exit 231
cat > "$MARK" <<MARKER
U2W MainVideo Passive Generation Seam Observer v8.36
software_version=$VER
product_type=$TYPE
mirror_sha1=$V834_SHIM_SHA1
relay_sha1=$V831_RELAY_SHA1
mirror_payload_changed=0
raw_relay_payload_changed=0
keyframe_helper_changed=0
observer_data_path=SIDE_CAR_ONLY
observer_h264_write=NEVER
observer_applecarplay_process_control=NEVER
observer_route_guidance_change=0
observer_ipc_policy=PASSIVE_PROC_SNAPSHOT_ONLY
MARKER
rm -f /tmp/u2w_mainvideo_seams.log /tmp/u2w_keyframe_ipc_topology.txt /tmp/u2w_generation_seam_observer.pid
sync
log 'installed v8.36 passive seam observer; exact v8.34 mirror/v8.31 relay/v8.35 helper unchanged'
rm -f "$P/u2w_generation_seam_observer.sh" "$P/u2wvideo-relay-start.cgi" "$P/u2wvideo-relay-status.cgi" "$P/u2wvideo-seam-log.cgi" "$P/once.sh"
exit 0
