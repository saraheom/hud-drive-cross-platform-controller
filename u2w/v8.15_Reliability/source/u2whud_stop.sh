#!/bin/sh
for pf in /tmp/u2whud_cast.pid /tmp/u2whud_discovery.pid /tmp/u2whud_ingress.pid; do
  if [ -f "$pf" ]; then P=$(cat "$pf" 2>/dev/null); [ -n "$P" ] && kill "$P" 2>/dev/null || true; fi
done
rm -f /tmp/u2whud_cast.pid /tmp/u2whud_discovery.pid /tmp/u2whud_ingress.pid
exit 0
