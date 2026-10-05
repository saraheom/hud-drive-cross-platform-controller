#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
MARK=/etc/u2w_v8_36_seam_observer.marker
log(){ echo "[U2W-v8.36-rollback] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 221; fi
for f in u2wvideo-relay-start-v835.cgi u2wvideo-relay-status-v835.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 222; }; done
op=""; [ -f /tmp/u2w_generation_seam_observer.pid ] && op=$(cat /tmp/u2w_generation_seam_observer.pid 2>/dev/null)
[ -n "$op" ] && kill "$op" 2>/dev/null || true
cp "$P/u2wvideo-relay-start-v835.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 223
cp "$P/u2wvideo-relay-status-v835.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 224
chmod 755 /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 225
rm -f /usr/bin/u2w_generation_seam_observer.sh /etc/boa/cgi-bin/u2wvideo-seam-log.cgi "$MARK" /tmp/u2w_generation_seam_observer.pid /tmp/u2w_mainvideo_seams.log /tmp/u2w_keyframe_ipc_topology.txt
sync
log 'rolled back v8.36 diagnostics only; v8.35 helper + v8.34 mirror + v8.31 relay remain unchanged'
rm -f "$P/u2wvideo-relay-start-v835.cgi" "$P/u2wvideo-relay-status-v835.cgi" "$P/once.sh"
exit 0
