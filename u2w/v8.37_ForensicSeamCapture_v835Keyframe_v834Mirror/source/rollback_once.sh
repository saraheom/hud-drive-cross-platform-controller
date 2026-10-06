#!/bin/sh
set -u
P=/tmp/update/tmp
log(){ echo "[U2W-v8.37-rollback] $*" > /dev/console; }
for f in u2w_generation_seam_observer-v836.sh u2wvideo-relay-start-v836.cgi u2wvideo-relay-status-v836.cgi u2wvideo-seam-log-v836.cgi; do
  [ -f "$P/$f" ] || { log "ABORT missing $f"; exit 241; }
done
op=""; [ -f /tmp/u2w_generation_seam_observer.pid ] && op=$(cat /tmp/u2w_generation_seam_observer.pid 2>/dev/null)
[ -n "$op" ] && kill "$op" 2>/dev/null || true
rm -f /tmp/u2w_generation_seam_observer.pid
cp "$P/u2w_generation_seam_observer-v836.sh" /usr/bin/u2w_generation_seam_observer.sh || exit 242
cp "$P/u2wvideo-relay-start-v836.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 243
cp "$P/u2wvideo-relay-status-v836.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 244
cp "$P/u2wvideo-seam-log-v836.cgi" /etc/boa/cgi-bin/u2wvideo-seam-log.cgi || exit 245
chmod 755 /usr/bin/u2w_generation_seam_observer.sh /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi /etc/boa/cgi-bin/u2wvideo-seam-log.cgi || exit 246
rm -f /etc/boa/cgi-bin/u2wvideo-forensic-status.cgi /etc/boa/cgi-bin/u2wvideo-forensic-bundle.cgi /etc/u2w_v8_37_forensic_seam.marker
rp=""; [ -f /tmp/u2w_mainvideo_relay.pid ] && rp=$(cat /tmp/u2w_mainvideo_relay.pid 2>/dev/null)
if [ -n "$rp" ] && kill -0 "$rp" 2>/dev/null; then
  /usr/bin/u2w_generation_seam_observer.sh >/tmp/u2w_generation_seam_observer.stdout 2>&1 &
fi
sync
log 'rolled back v8.37 diagnostics to v8.36 observer; mirror/relay/helper never changed'
rm -f "$P"/u2w_generation_seam_observer-v836.sh "$P"/u2wvideo-relay-start-v836.cgi "$P"/u2wvideo-relay-status-v836.cgi "$P"/u2wvideo-seam-log-v836.cgi "$P/once.sh"
exit 0
