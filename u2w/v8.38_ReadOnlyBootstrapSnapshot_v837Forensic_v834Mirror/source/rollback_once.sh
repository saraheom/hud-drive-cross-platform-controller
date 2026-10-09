#!/bin/sh
set -u
P=/tmp/update/tmp
log(){ echo "[U2W-v8.38-rollback] $*" > /dev/console; }
for f in v837-u2w_generation_seam_observer.sh v837-u2wvideo-relay-start.cgi v837-u2wvideo-relay-status.cgi v837-u2wvideo-seam-log.cgi v837-u2wvideo-forensic-status.cgi v837-u2wvideo-forensic-bundle.cgi; do [ -f "$P/$f" ] || exit 301; done
op=""; [ -f /tmp/u2w_generation_seam_observer.pid ] && op=$(cat /tmp/u2w_generation_seam_observer.pid 2>/dev/null)
[ -n "$op" ] && kill "$op" 2>/dev/null || true
rm -f /tmp/u2w_generation_seam_observer.pid
rm -f /etc/init.d/S98u2w_v838_bootstrap_observer /etc/rcS.d/S98u2w_v838_bootstrap_observer /usr/bin/u2w_v838_bootstrap_observer_boot.sh
cp "$P/v837-u2w_generation_seam_observer.sh" /usr/bin/u2w_generation_seam_observer.sh || exit 302
for f in u2wvideo-relay-start.cgi u2wvideo-relay-status.cgi u2wvideo-seam-log.cgi u2wvideo-forensic-status.cgi u2wvideo-forensic-bundle.cgi; do
  cp "$P/v837-$f" "/etc/boa/cgi-bin/$f" || exit 303
done
chmod 755 /usr/bin/u2w_generation_seam_observer.sh /etc/boa/cgi-bin/u2wvideo-*.cgi || exit 304
rm -f /etc/u2w_v8_38_bootstrap_snapshot.marker /etc/boa/cgi-bin/u2wvideo-bootstrap-current.cgi /etc/boa/cgi-bin/u2wvideo-bootstrap-previous.cgi /tmp/u2w_v838_bootstrap_previous.h264 /tmp/u2w_v838_bootstrap_previous.meta
rp=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && rp=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
if [ -n "$rp" ] && kill -0 "$rp" 2>/dev/null; then /usr/bin/u2w_generation_seam_observer.sh >/tmp/u2w_generation_seam_observer.stdout 2>&1 & fi
sync
log 'rolled back v8.38 bootstrap sidecar to v8.37 forensic observer; mirror/relay/helper unchanged'
rm -f "$P"/v837-* "$P"/once.sh
exit 0
