#!/bin/sh
set -u
P=/tmp/update/tmp
for f in v838-libu2w_rgd_preload.so v838-u2whud-start.cgi v838-u2whud-status.cgi; do [ -f "$P/$f" ] || exit 401; done
cp "$P/v838-libu2w_rgd_preload.so" /usr/lib/u2wrgd/libu2w_rgd_preload.so || exit 402
cp "$P/v838-u2whud-start.cgi" /etc/boa/cgi-bin/u2whud-start.cgi || exit 403
cp "$P/v838-u2whud-status.cgi" /etc/boa/cgi-bin/u2whud-status.cgi || exit 403
chmod 755 /usr/lib/u2wrgd/libu2w_rgd_preload.so /etc/boa/cgi-bin/u2whud-start.cgi /etc/boa/cgi-bin/u2whud-status.cgi || exit 404
rm -f /etc/u2w_v8_39_session_boundary.marker
sync
rm -f "$P"/v838-* "$P"/once.sh
exit 0
