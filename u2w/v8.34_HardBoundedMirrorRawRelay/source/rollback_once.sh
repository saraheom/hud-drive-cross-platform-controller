#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null); TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp; LIB=/usr/lib/u2wvideo; SHIM=$LIB/libu2w_mainvideo_live.so
ACTIVE_V834_SHA1=b982322ee65fd45405ab40f98512dbd76450976b
V833_SHIM_SHA1=67ec2d1d69a50096c0b14e26048fd7b2a00bde08
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
[ "$VER" = "2021.03.06.1343" ] && [ "$TYPE" = "U2W" ] || exit 241
for f in libu2w_mainvideo_live_v833.so u2w_mainvideo_relay_v833 u2wvideo-relay-start-v833.cgi u2wvideo-relay-stop-v833.cgi u2wvideo-relay-status-v833.cgi; do [ -f "$P/$f" ] || exit 242; done
CUR_SHIM=$(sha1sum "$SHIM" 2>/dev/null | awk '{print $1}')
[ "$CUR_SHIM" = "$ACTIVE_V834_SHA1" ] || exit 248
PAYLOAD_SHIM=$(sha1sum "$P/libu2w_mainvideo_live_v833.so" 2>/dev/null | awk '{print $1}')
PAYLOAD_RELAY=$(sha1sum "$P/u2w_mainvideo_relay_v833" 2>/dev/null | awk '{print $1}')
[ "$PAYLOAD_SHIM" = "$V833_SHIM_SHA1" ] || exit 249
[ "$PAYLOAD_RELAY" = "$V831_RELAY_SHA1" ] || exit 250
# Stop ONLY our standalone custom relay after verifying the PID still points to it.
PF=/tmp/u2w_mainvideo_relay.pid
if [ -f "$PF" ]; then
  p=$(cat "$PF" 2>/dev/null || true)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    exe=$(readlink "/proc/$p/exe" 2>/dev/null || true)
    [ "$exe" = "$LIB/u2w_mainvideo_relay" ] && kill "$p" 2>/dev/null || true
  fi
fi
rm -f "$PF" /tmp/u2w_mainvideo_live.next
cp "$P/libu2w_mainvideo_live_v833.so" "$SHIM" || exit 243
cp "$P/u2w_mainvideo_relay_v833" "$LIB/u2w_mainvideo_relay" || exit 244
cp "$P/u2wvideo-relay-start-v833.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 245
cp "$P/u2wvideo-relay-stop-v833.cgi" /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi || exit 246
cp "$P/u2wvideo-relay-status-v833.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 247
chmod 755 "$SHIM" "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi
rm -f /etc/u2w_v8_34_hard_bounded_mirror.marker
cat > /etc/u2w_v8_33_lossless_mirror.marker <<MARKER
U2W MainVideo Lossless Mirror + v8.31 Raw Relay v8.33 rollback
software_version=$VER
product_type=$TYPE
restored_shim_sha1=$V833_SHIM_SHA1
restored_raw_relay_sha1=$V831_RELAY_SHA1
applecarplay_signal_policy=NEVER
applecarplay_restart_policy=NEVER
MARKER
sync
rm -f "$P"/*v833* "$P/once.sh"
exit 0
