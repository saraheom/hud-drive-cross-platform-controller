#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n\r\n'
echo 'U2W HUD-as-STA KivicCast Home Test v8.13 status'
echo "marker=$(test -f /etc/u2whud_bridge_v8_13.marker && echo YES || echo NO)"
P=$(cat /tmp/u2whud_cast.pid 2>/dev/null)
echo "cast_pid=$P"
if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then echo 'cast_process=RUNNING'; else echo 'cast_process=STOPPED'; fi
echo '--- cast log ---'
cat /tmp/u2whud_cast.log 2>/dev/null || echo '(none)'
echo '--- wlan0 ---'
ifconfig wlan0 2>&1 || true
echo '--- ARP table (look for HUD station after mode 6 connect) ---'
cat /proc/net/arp 2>/dev/null || true
echo '--- DHCP leases (locations used by common BusyBox builds) ---'
for f in /tmp/udhcpd.leases /var/lib/misc/udhcpd.leases /var/lib/udhcpd/udhcpd.leases; do
  if [ -f "$f" ]; then echo "[$f]"; od -An -tx1 -v "$f" 2>/dev/null | tail -40; fi
done
echo '--- listeners ---'
netstat -lntup 2>&1 | grep -E '(:80 |:15320 |:15330 |:67 )' || true
echo '--- hostapd station capacity hints ---'
grep -E '^(interface|ssid|channel|max_num_sta|ap_max_inactivity)=' /etc/hostapd.conf 2>/dev/null || true
