#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\n\r\n'
echo 'U2W Main CarPlay Video Exporter v8.18 fd-reselection'
[ -f /etc/u2w_v8_18_fd_reselect.marker ] && echo 'fd_reselect=INSTALLED' || echo 'fd_reselect=NOT_INSTALLED'
[ -f /etc/u2w_mainvideo_v8_11.marker ] && echo 'mainvideo_exporter=INSTALLED' || echo 'mainvideo_exporter=NOT_INSTALLED'
echo "software_version=$(cat /etc/software_version 2>/dev/null)"
echo "product_type=$(cat /etc/box_product_type 2>/dev/null)"
echo "AppleCarPlay_pid=$(pidof AppleCarPlay 2>/dev/null)"
echo "saved_AppleCarPlay_sha1=$(sha1sum /usr/lib/u2wvideo/AppleCarPlay 2>/dev/null | awk '{print $1}')"
echo "active_shim_sha1=$(sha1sum /usr/lib/u2wvideo/libu2w_mainvideo_live.so 2>/dev/null | awk '{print $1}')"
if [ -f /tmp/u2w_mainvideo_live.h264 ]; then
  echo "live_file_bytes=$(wc -c < /tmp/u2w_mainvideo_live.h264 2>/dev/null)"
else
  echo 'live_file_bytes=0'
fi
if [ -f /tmp/u2w_mainvideo_status.txt ]; then
  echo
  cat /tmp/u2w_mainvideo_status.txt
else
  echo 'exporter_active=NO'
fi
echo
echo 'stream_endpoint=http://192.168.50.2/cgi-bin/u2wvideo-main-stream.cgi'
echo 'snapshot_endpoint=http://192.168.50.2/cgi-bin/u2wvideo-main-snapshot.cgi'
echo 'route_endpoint=http://192.168.50.2/tmp/u2w_rgd_live.json'
