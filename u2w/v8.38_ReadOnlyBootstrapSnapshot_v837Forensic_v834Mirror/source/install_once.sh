#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
MARK=/etc/u2w_v8_38_bootstrap_snapshot.marker
MIRROR=/usr/lib/u2wvideo/libu2w_mainvideo_live.so
RELAY=/usr/lib/u2wvideo/u2w_mainvideo_relay
V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
log(){ echo "[U2W-v8.38] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 281; fi
[ -f /etc/u2w_v8_37_forensic_seam.marker ] || { log 'ABORT v8.37 marker missing'; exit 282; }
[ -f /etc/u2w_v8_35_bounded_keyframe.marker ] || { log 'ABORT v8.35 marker missing'; exit 283; }
[ -f /etc/u2w_v8_34_hard_bounded_mirror.marker ] || { log 'ABORT v8.34 mirror marker missing'; exit 284; }
[ "$(sha1sum "$MIRROR" 2>/dev/null | awk '{print $1}')" = "$V834_SHIM_SHA1" ] || { log 'ABORT v8.34 mirror bytes not exact'; exit 285; }
[ "$(sha1sum "$RELAY" 2>/dev/null | awk '{print $1}')" = "$V831_RELAY_SHA1" ] || { log 'ABORT v8.31 relay bytes not exact'; exit 286; }
for f in u2w_generation_seam_observer.sh u2w_v838_bootstrap_observer_boot.sh u2wvideo-relay-start.cgi u2wvideo-relay-status.cgi u2wvideo-seam-log.cgi u2wvideo-forensic-status.cgi u2wvideo-forensic-bundle.cgi u2wvideo-bootstrap-current.cgi u2wvideo-bootstrap-previous.cgi; do
  [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 287; }
done
cp "$P/u2w_generation_seam_observer.sh" /usr/bin/u2w_generation_seam_observer.sh || exit 288
cp "$P/u2w_v838_bootstrap_observer_boot.sh" /usr/bin/u2w_v838_bootstrap_observer_boot.sh || exit 288
mkdir -p /etc/init.d /etc/rcS.d || exit 288
cp "$P/u2w_v838_bootstrap_observer_boot.sh" /etc/init.d/S98u2w_v838_bootstrap_observer || exit 288
ln -sf ../init.d/S98u2w_v838_bootstrap_observer /etc/rcS.d/S98u2w_v838_bootstrap_observer || exit 288
for f in u2wvideo-relay-start.cgi u2wvideo-relay-status.cgi u2wvideo-seam-log.cgi u2wvideo-forensic-status.cgi u2wvideo-forensic-bundle.cgi u2wvideo-bootstrap-current.cgi u2wvideo-bootstrap-previous.cgi; do
  cp "$P/$f" "/etc/boa/cgi-bin/$f" || exit 289
done
chmod 755 /usr/bin/u2w_generation_seam_observer.sh /usr/bin/u2w_v838_bootstrap_observer_boot.sh /etc/init.d/S98u2w_v838_bootstrap_observer /etc/boa/cgi-bin/u2wvideo-*.cgi || exit 290
cat > "$MARK" <<MARKER
U2W MainVideo Read-Only Startup Bootstrap Snapshot v8.38
software_version=$VER
product_type=$TYPE
mirror_sha1=$V834_SHIM_SHA1
relay_sha1=$V831_RELAY_SHA1
mirror_payload_changed=0
raw_relay_payload_changed=0
keyframe_helper_changed=0
snapshot_previous_generation=PASSIVE_READ_ONLY_COPY
snapshot_observer_autostart=YES_READ_ONLY_ONLY
snapshot_current_generation=ON_DEMAND_READ_ONLY_COPY
snapshot_h264_parse=IPHONE_ONLY
snapshot_tcp15332_change=0
snapshot_applecarplay_process_control=NEVER
snapshot_route_guidance_change=0
MARKER
rm -f /tmp/u2w_v838_bootstrap_previous.h264 /tmp/u2w_v838_bootstrap_previous.meta
op=""; [ -f /tmp/u2w_generation_seam_observer.pid ] && op=$(cat /tmp/u2w_generation_seam_observer.pid 2>/dev/null)
[ -n "$op" ] && kill "$op" 2>/dev/null || true
rm -f /tmp/u2w_generation_seam_observer.pid
/usr/bin/u2w_v838_bootstrap_observer_boot.sh start
sync
log 'installed v8.38 read-only bootstrap sidecar; exact v8.34 mirror/v8.31 relay/v8.35 helper unchanged'
rm -f "$P"/u2w_generation_seam_observer.sh "$P"/u2w_v838_bootstrap_observer_boot.sh "$P"/u2wvideo-relay-start.cgi "$P"/u2wvideo-relay-status.cgi "$P"/u2wvideo-seam-log.cgi "$P"/u2wvideo-forensic-status.cgi "$P"/u2wvideo-forensic-bundle.cgi "$P"/u2wvideo-bootstrap-current.cgi "$P"/u2wvideo-bootstrap-previous.cgi "$P"/once.sh
exit 0
