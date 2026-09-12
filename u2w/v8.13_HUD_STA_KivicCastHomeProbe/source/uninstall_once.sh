#!/bin/sh
DIR=/usr/lib/u2whud
[ -x "$DIR/u2whud_stop.sh" ] && "$DIR/u2whud_stop.sh" >/dev/null 2>&1 || true
rm -f /etc/boa/cgi-bin/u2whud-start.cgi /etc/boa/cgi-bin/u2whud-stop.cgi /etc/boa/cgi-bin/u2whud-status.cgi
rm -rf "$DIR"
rm -f /etc/u2whud_bridge_v8_13.marker /tmp/u2whud_cast.log /tmp/u2whud_cast.pid
sync
rm -f /tmp/update/tmp/once.sh
exit 0
