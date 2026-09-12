#!/bin/sh
if [ -f /tmp/u2whud_cast.pid ]; then
  P=$(cat /tmp/u2whud_cast.pid 2>/dev/null)
  [ -n "$P" ] && kill "$P" 2>/dev/null || true
fi
rm -f /tmp/u2whud_cast.pid
exit 0
