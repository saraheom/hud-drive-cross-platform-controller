#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
SID=""; [ -f /tmp/u2whud_session_id ] && SID=$(cat /tmp/u2whud_session_id 2>/dev/null)
rm -f /tmp/u2whud_session_discovery /tmp/u2whud_session_client \
      /tmp/u2whud_session_established /tmp/u2whud_session_fallback \
      /tmp/u2whud_session_live
# Deliberately preserve ingress/discovery/cast daemons and the last good frame.
# The iPhone app returns the HUD to mode 4; a later Start creates a fresh session
# without paying the old daemon teardown/rebind/discovery race.
echo "U2W v8.15.1 HUD display session idled; relay daemons preserved. session_id=$SID"
