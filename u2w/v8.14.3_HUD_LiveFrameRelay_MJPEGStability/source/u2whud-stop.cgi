#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
/usr/lib/u2whud/u2whud_stop.sh >/dev/null 2>&1 || true
rm -f /tmp/u2whud_latest.jpg /tmp/u2whud_latest.new
echo 'U2W v8.14 live frame relay stopped.'
