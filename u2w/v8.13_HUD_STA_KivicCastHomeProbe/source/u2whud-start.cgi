#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W HUD-as-STA KivicCast Home Test v8.13'
echo 'Starting known-image KivicCast server on U2W AP host 192.168.50.2.'
/usr/lib/u2whud/u2whud_stop.sh >/dev/null 2>&1 || true
rm -f /tmp/u2whud_cast.log
/usr/lib/u2whud/u2whud_cast_test >/tmp/u2whud_cast.log 2>&1 &
P=$!
echo "$P" >/tmp/u2whud_cast.pid
echo "cast_pid=$P"
echo 'Server is waiting on UDP/15320 for KVMJPEG/1.0 discovery from the HUD.'
echo 'Now use HUD Controller v90.35.2: HUD -> U2W Wi-Fi home diagnostic -> Start home bridge test.'
echo 'Keep iPhone connected to U2W/Carlinkit Wi-Fi. Do NOT join HUDWAY Drive Wi-Fi.'
