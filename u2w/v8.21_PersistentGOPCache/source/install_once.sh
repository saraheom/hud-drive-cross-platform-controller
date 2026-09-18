#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
BASEMARK=/etc/u2w_v8_20_validated_gop.marker
MARK=/etc/u2w_v8_21_gop_cache.marker
DST=/etc/boa/cgi-bin/u2wvideo-main-stream.cgi
START=/etc/boa/cgi-bin/u2wvideo-cache-start.cgi
STATUS=/etc/boa/cgi-bin/u2wvideo-cache-status.cgi
LIB=/usr/lib/u2wvideo
log(){ echo "[U2W-v8.21] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 91; fi
[ -f "$BASEMARK" ] || { log 'ABORT v8.20 marker missing'; exit 92; }
[ -f /etc/u2w_mainvideo_v8_11.marker ] || { log 'ABORT v8.11 MainVideo marker missing'; exit 93; }
for f in u2w_mainvideo_cache u2w_mainvideo_streamer u2wvideo-cache-start.cgi u2wvideo-cache-status.cgi; do
  [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 94; }
done
# Stop only an older v8.21 cache helper if present. AppleCarPlay/exporter/route/media are untouched.
if [ -f /tmp/u2w_mainvideo_cache.pid ]; then
  old=$(cat /tmp/u2w_mainvideo_cache.pid 2>/dev/null || true)
  [ -n "$old" ] && kill "$old" 2>/dev/null || true
fi
rm -f /tmp/u2w_mainvideo_cache.pid /tmp/u2w_mainvideo_cache_ready /tmp/u2w_mainvideo_gop_cache.h264
mkdir -p "$LIB" || exit 95
cp "$P/u2w_mainvideo_cache" "$LIB/u2w_mainvideo_cache" || exit 96
cp "$P/u2w_mainvideo_streamer" "$DST" || exit 97
cp "$P/u2wvideo-cache-start.cgi" "$START" || exit 98
cp "$P/u2wvideo-cache-status.cgi" "$STATUS" || exit 99
chmod 755 "$LIB/u2w_mainvideo_cache" "$DST" "$START" "$STATUS" || exit 100
cat > "$MARK" <<MARKER
U2W MainVideo Persistent GOP Cache v8.21
software_version=$VER
product_type=$TYPE
base=v8.20+v8.11
architecture=continuous_decoder_safe_gop_cache
applecarplay_hook_changed=0
exporter_changed=0
route_media_changed=0
http_not_ready_behavior=503_fail_fast
cache_start_endpoint=/cgi-bin/u2wvideo-cache-start.cgi
cache_status_endpoint=/cgi-bin/u2wvideo-cache-status.cgi
MARKER
sync
log 'installed persistent GOP cache + fail-fast streamer; AppleCarPlay/exporter/route/media untouched'
rm -f "$P/u2w_mainvideo_cache" "$P/u2w_mainvideo_streamer" "$P/u2wvideo-cache-start.cgi" "$P/u2wvideo-cache-status.cgi" "$P/once.sh"
exit 0
