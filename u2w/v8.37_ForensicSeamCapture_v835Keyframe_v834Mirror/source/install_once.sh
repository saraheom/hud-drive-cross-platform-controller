#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
MARK=/etc/u2w_v8_37_forensic_seam.marker
MIRROR=/usr/lib/u2wvideo/libu2w_mainvideo_live.so
RELAY=/usr/lib/u2wvideo/u2w_mainvideo_relay
V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
log(){ echo "[U2W-v8.37] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 221; fi
[ -f /etc/u2w_v8_35_bounded_keyframe.marker ] || { log 'ABORT v8.35 marker missing'; exit 222; }
[ -f /etc/u2w_v8_34_hard_bounded_mirror.marker ] || { log 'ABORT v8.34 mirror marker missing'; exit 223; }
[ -f /etc/u2w_v8_36_seam_observer.marker ] || { log 'ABORT v8.36 seam observer marker missing'; exit 224; }
[ "$(sha1sum "$MIRROR" 2>/dev/null | awk '{print $1}')" = "$V834_SHIM_SHA1" ] || { log 'ABORT v8.34 mirror bytes not exact'; exit 225; }
[ "$(sha1sum "$RELAY" 2>/dev/null | awk '{print $1}')" = "$V831_RELAY_SHA1" ] || { log 'ABORT v8.31 relay bytes not exact'; exit 226; }
for f in u2w_generation_seam_observer.sh u2wvideo-relay-start.cgi u2wvideo-relay-status.cgi u2wvideo-seam-log.cgi u2wvideo-forensic-status.cgi u2wvideo-forensic-bundle.cgi; do
  [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 227; }
done
# Diagnostics only. Never replace MIRROR/RELAY/helper and never signal CarPlay.
cp "$P/u2w_generation_seam_observer.sh" /usr/bin/u2w_generation_seam_observer.sh || exit 228
cp "$P/u2wvideo-relay-start.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 229
cp "$P/u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 230
cp "$P/u2wvideo-seam-log.cgi" /etc/boa/cgi-bin/u2wvideo-seam-log.cgi || exit 231
cp "$P/u2wvideo-forensic-status.cgi" /etc/boa/cgi-bin/u2wvideo-forensic-status.cgi || exit 232
cp "$P/u2wvideo-forensic-bundle.cgi" /etc/boa/cgi-bin/u2wvideo-forensic-bundle.cgi || exit 233
chmod 755 /usr/bin/u2w_generation_seam_observer.sh /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi /etc/boa/cgi-bin/u2wvideo-seam-log.cgi /etc/boa/cgi-bin/u2wvideo-forensic-status.cgi /etc/boa/cgi-bin/u2wvideo-forensic-bundle.cgi || exit 234
cat > "$MARK" <<MARKER
U2W MainVideo Forensic Generation Seam Capture v8.37
software_version=$VER
product_type=$TYPE
mirror_sha1=$V834_SHIM_SHA1
relay_sha1=$V831_RELAY_SHA1
mirror_payload_changed=0
raw_relay_payload_changed=0
keyframe_helper_changed=0
observer_data_path=SIDE_CAR_ONLY
observer_h264_write=NEVER
observer_tcp15332_open=NEVER
observer_applecarplay_process_control=NEVER
observer_route_guidance_change=0
observer_ipc_policy=PASSIVE_PROC_SNAPSHOT_ONLY
boundary_sample_bytes=4096
retained_seam_groups=128
MARKER
mkdir -p /tmp/u2w_v837_seam_evidence 2>/dev/null || true
# Restart only the diagnostic observer so v8.37 code is active immediately.
op=""; [ -f /tmp/u2w_generation_seam_observer.pid ] && op=$(cat /tmp/u2w_generation_seam_observer.pid 2>/dev/null)
[ -n "$op" ] && kill "$op" 2>/dev/null || true
rm -f /tmp/u2w_generation_seam_observer.pid
rp=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && rp=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
if [ -n "$rp" ] && kill -0 "$rp" 2>/dev/null; then
  /usr/bin/u2w_generation_seam_observer.sh >/tmp/u2w_generation_seam_observer.stdout 2>&1 &
fi
sync
log 'installed v8.37 forensic seam sidecar; exact v8.34 mirror/v8.31 relay/v8.35 helper unchanged'
rm -f "$P/u2w_generation_seam_observer.sh" "$P/u2wvideo-relay-start.cgi" "$P/u2wvideo-relay-status.cgi" "$P/u2wvideo-seam-log.cgi" "$P/u2wvideo-forensic-status.cgi" "$P/u2wvideo-forensic-bundle.cgi" "$P/once.sh"
exit 0
