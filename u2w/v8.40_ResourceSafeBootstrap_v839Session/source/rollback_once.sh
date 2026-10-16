#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null); TYPE=$(cat /etc/box_product_type 2>/dev/null); P=/tmp/update/tmp
MARK=/etc/u2w_v8_40_resource_safe_bootstrap.marker
RGD=/usr/lib/u2wrgd/libu2w_rgd_preload.so
log(){ echo "[U2W-v8.40-rollback] $*" >/dev/console; }
[ "$VER" = "2021.03.06.1343" ] && [ "$TYPE" = "U2W" ] || exit 421
[ -f "$MARK" ] || { log 'ABORT v8.40 marker missing'; exit 422; }
for f in v839-libu2w_rgd_preload.so v838-u2wvideo-bootstrap-current.cgi v838-u2wvideo-bootstrap-previous.cgi v838-u2wvideo-relay-status.cgi; do [ -f "$P/$f" ] || exit 423; done
cp "$P/v839-libu2w_rgd_preload.so" "$RGD" || exit 424
cp "$P/v838-u2wvideo-bootstrap-current.cgi" /etc/boa/cgi-bin/u2wvideo-bootstrap-current.cgi || exit 425
cp "$P/v838-u2wvideo-bootstrap-previous.cgi" /etc/boa/cgi-bin/u2wvideo-bootstrap-previous.cgi || exit 425
cp "$P/v838-u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 425
rm -f /etc/boa/cgi-bin/u2wresource-status.cgi "$MARK"
chmod 755 "$RGD" /etc/boa/cgi-bin/u2wvideo-bootstrap-current.cgi /etc/boa/cgi-bin/u2wvideo-bootstrap-previous.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 426
sync
log 'rolled back v8.40 changes to v8.39/v8.38 baseline; reboot required'
rm -f "$P"/v839-libu2w_rgd_preload.so "$P"/v838-u2wvideo-bootstrap-current.cgi "$P"/v838-u2wvideo-bootstrap-previous.cgi "$P"/v838-u2wvideo-relay-status.cgi "$P"/once.sh
exit 0
