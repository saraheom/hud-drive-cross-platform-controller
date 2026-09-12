#!/bin/sh
[ -x /usr/lib/u2whud/u2whud_stop.sh ] && /usr/lib/u2whud/u2whud_stop.sh >/dev/null 2>&1 || true
rm -f /etc/u2whud_bridge_v8_14_3.marker
rm -f /etc/boa/cgi-bin/u2whud-start.cgi /etc/boa/cgi-bin/u2whud-stop.cgi /etc/boa/cgi-bin/u2whud-status.cgi
rm -rf /usr/lib/u2whud
sync
exit 0
