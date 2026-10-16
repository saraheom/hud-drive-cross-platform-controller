#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null); TYPE=$(cat /etc/box_product_type 2>/dev/null); P=/tmp/update/tmp
MARK=/etc/u2w_v8_40_resource_safe_bootstrap.marker
RGD=/usr/lib/u2wrgd/libu2w_rgd_preload.so
log(){ echo "[U2W-v8.40] $*" >/dev/console; }
[ "$VER" = "2021.03.06.1343" ] && [ "$TYPE" = "U2W" ] || { log "ABORT target $TYPE/$VER"; exit 401; }
[ -f /etc/u2w_v8_39_session_boundary.marker ] || { log 'ABORT v8.39 marker missing'; exit 402; }
[ -f /etc/u2w_v8_38_bootstrap_snapshot.marker ] || { log 'ABORT v8.38 marker missing'; exit 403; }
[ "$(sha1sum "$RGD" 2>/dev/null | awk '{print $1}')" = "2052b3aac2f979b17fef683ab6a7f202b60cfea5" ] || { log 'ABORT Route Guidance preload is not v8.39 baseline'; exit 404; }
[ "$(sha1sum /etc/boa/cgi-bin/u2wvideo-bootstrap-current.cgi 2>/dev/null | awk '{print $1}')" = "0fb018fa5b6ae210d938a3edd692d0fdd729129f" ] || { log 'ABORT bootstrap-current is not v8.38 baseline'; exit 405; }
[ "$(sha1sum /etc/boa/cgi-bin/u2wvideo-bootstrap-previous.cgi 2>/dev/null | awk '{print $1}')" = "12f73ff80b482cb0c69340992327bb53e3af4098" ] || { log 'ABORT bootstrap-previous is not v8.38 baseline'; exit 406; }
[ "$(sha1sum /etc/boa/cgi-bin/u2wvideo-relay-status.cgi 2>/dev/null | awk '{print $1}')" = "46408099eb259606dedacfaa28fefd72dcd651f1" ] || { log 'ABORT relay-status is not v8.38 baseline'; exit 407; }
for f in libu2w_rgd_preload_v840.so u2wvideo-bootstrap-current.cgi u2wvideo-bootstrap-previous.cgi u2wvideo-relay-status.cgi u2wresource-status.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 408; }; done
cp "$P/libu2w_rgd_preload_v840.so" "$RGD" || exit 409
for f in u2wvideo-bootstrap-current.cgi u2wvideo-bootstrap-previous.cgi u2wvideo-relay-status.cgi u2wresource-status.cgi; do cp "$P/$f" "/etc/boa/cgi-bin/$f" || exit 410; done
chmod 755 "$RGD" /etc/boa/cgi-bin/u2wvideo-bootstrap-current.cgi /etc/boa/cgi-bin/u2wvideo-bootstrap-previous.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi /etc/boa/cgi-bin/u2wresource-status.cgi || exit 411
# Remove leaked per-request v8.38 snapshot copies and incomplete publisher temps.
rm -f /tmp/u2w_v838_bootstrap_current_*.h264 /tmp/u2w_v838_bootstrap_previous_[0-9]*.h264 /tmp/u2w_v838_bootstrap_previous_[0-9]*.meta 2>/dev/null || true
rm -f /tmp/u2w_rgd_live.json.tmp /tmp/u2w_media_live.json.tmp /tmp/u2w_rgd_status.txt.tmp 2>/dev/null || true
cat >"$MARK" <<META
U2W Resource-Safe Bootstrap v8.40
software_version=$VER
product_type=$TYPE
base_v839=YES
base_v838=YES
bootstrap_request_temp_h264=NONE
bootstrap_snapshot_policy=ZERO_COPY_PINNED_INODE_FIXED_PREFIX
rgd_atomic_publish_requires_full_write=YES
rgd_preserve_last_good_on_write_failure=YES
rgd_diagnostic_files_bounded_512KiB_each=YES
legacy_bootstrap_temp_cleanup=YES
mainvideo_mirror_changed=NO
mainvideo_raw_relay_changed=NO
applecarplay_process_control=NEVER
META
sync
log 'installed v8.40; reboot required for resource-safe RGD preload; MainVideo mirror/raw relay unchanged'
rm -f "$P"/libu2w_rgd_preload_v840.so "$P"/u2wvideo-bootstrap-current.cgi "$P"/u2wvideo-bootstrap-previous.cgi "$P"/u2wvideo-relay-status.cgi "$P"/u2wresource-status.cgi "$P"/once.sh
exit 0
