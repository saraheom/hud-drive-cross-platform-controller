#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W HUD Live Frame Relay v8.14.2 status'
echo "marker=$([ -f /etc/u2whud_bridge_v8_14_2.marker ] && echo YES || echo NO)"
for n in ingress discovery cast; do
 pf="/tmp/u2whud_${n}.pid"; p=""; [ -f "$pf" ] && p=$(cat "$pf" 2>/dev/null)
 echo "${n}_pid=$p"
 if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo "${n}_process=RUNNING"; else echo "${n}_process=STOPPED"; fi
done
[ -f /tmp/u2whud_latest.jpg ] && echo "latest_frame_bytes=$(wc -c </tmp/u2whud_latest.jpg 2>/dev/null)" || echo 'latest_frame_bytes=0'
if netstat -nt 2>/dev/null | grep -q ':15330 .*ESTABLISHED'; then echo 'hud_mjpeg_established=YES'; else echo 'hud_mjpeg_established=NO'; fi
echo '--- ingress log ---'; tail -n 20 /tmp/u2whud_ingress.log 2>/dev/null || true
echo '--- discovery log ---'; tail -n 30 /tmp/u2whud_discovery.log 2>/dev/null || true
echo '--- cast log ---'; tail -n 30 /tmp/u2whud_cast.log 2>/dev/null || true
echo '--- wlan0 ---'; ifconfig wlan0 2>&1 || true
echo '--- ARP table ---'; cat /proc/net/arp 2>&1 || true
echo '--- listeners ---'; netstat -lntup 2>&1 | grep -E '(:80 |:15320 |:15330 |:15331 |:67 )' || true
