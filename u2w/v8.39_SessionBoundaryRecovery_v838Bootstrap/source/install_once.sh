#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null); TYPE=$(cat /etc/box_product_type 2>/dev/null); P=/tmp/update/tmp
MARK=/etc/u2w_v8_39_session_boundary.marker
RGD=/usr/lib/u2wrgd/libu2w_rgd_preload.so
OLD_RGD_SHA1=2dca814e86be234bdbe7c8effdd381b2f16bd0fa
log(){ echo "[U2W-v8.39] $*" >/dev/console; }
[ "$VER" = "2021.03.06.1343" ] && [ "$TYPE" = "U2W" ] || { log "ABORT target $TYPE/$VER"; exit 391; }
[ -f /etc/u2w_v8_38_bootstrap_snapshot.marker ] || { log 'ABORT v8.38 marker missing'; exit 392; }
[ "$(sha1sum "$RGD" 2>/dev/null | awk '{print $1}')" = "$OLD_RGD_SHA1" ] || { log 'ABORT Route Guidance preload is not v8.38 baseline'; exit 393; }
for f in libu2w_rgd_preload_v839.so u2whud-start.cgi u2whud-status.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 394; }; done
cp "$P/libu2w_rgd_preload_v839.so" "$RGD" || exit 395
cp "$P/u2whud-start.cgi" /etc/boa/cgi-bin/u2whud-start.cgi || exit 396
cp "$P/u2whud-status.cgi" /etc/boa/cgi-bin/u2whud-status.cgi || exit 396
chmod 755 "$RGD" /etc/boa/cgi-bin/u2whud-start.cgi /etc/boa/cgi-bin/u2whud-status.cgi || exit 397
cat >"$MARK" <<EOF
U2W Session Boundary Recovery v8.39
software_version=$VER
product_type=$TYPE
base_v838=YES
hud_helpers_fresh_each_map_session=YES
route_guidance_new_wifi_identify_rearm=YES
mainvideo_mirror_changed=NO
mainvideo_relay_changed=NO
bootstrap_snapshot_changed=NO
applecarplay_process_control=NEVER
EOF
sync
log 'installed v8.39; reboot required to map new RGD preload; MainVideo v8.38 path unchanged'
rm -f "$P"/libu2w_rgd_preload_v839.so "$P"/u2whud-start.cgi "$P"/u2whud-status.cgi "$P"/once.sh
exit 0
