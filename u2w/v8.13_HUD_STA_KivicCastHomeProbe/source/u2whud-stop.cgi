#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
/usr/lib/u2whud/u2whud_stop.sh >/dev/null 2>&1 || true
echo 'U2W v8.13 KivicCast known-image server stopped.'
