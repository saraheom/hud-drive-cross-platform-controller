#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
SHIM=$LIB/libu2w_mainvideo_live.so
V833_SHIM_SHA1=67ec2d1d69a50096c0b14e26048fd7b2a00bde08
V811_SHIM_SHA1=7ab8e227893277c9c1135a398e24e41c8f84d4df
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
V832_RELAY_SHA1=b07824e46aee104157135af91ec7edb467c7afee
log(){ echo "[U2W-v8.33-ROLLBACK] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 241; fi
CUR=$(sha1sum "$SHIM" 2>/dev/null | awk '{print $1}')
[ "$CUR" = "$V833_SHIM_SHA1" ] || { log "ABORT active shim not v8.33 sha1=$CUR"; exit 242; }
CURR=$(sha1sum "$LIB/u2w_mainvideo_relay" 2>/dev/null | awk '{print $1}')
[ "$CURR" = "$V831_RELAY_SHA1" ] || { log "ABORT active relay not exact v8.31 raw sha1=$CURR"; exit 243; }
PF=/tmp/u2w_mainvideo_relay.pid
if [ -f "$PF" ]; then
 p=$(cat "$PF" 2>/dev/null || true)
 if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then exe=$(readlink "/proc/$p/exe" 2>/dev/null || true); [ "$exe" = "$LIB/u2w_mainvideo_relay" ] && kill "$p" 2>/dev/null || true; fi
fi
rm -f "$PF" /tmp/u2w_mainvideo_live.next
cp "$P/libu2w_mainvideo_live_v811.so" "$SHIM" || exit 244
cp "$P/u2w_mainvideo_relay_v832" "$LIB/u2w_mainvideo_relay" || exit 245
cp "$P/u2wvideo-relay-start-v832.cgi" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi || exit 246
cp "$P/u2wvideo-relay-stop-v832.cgi" /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi || exit 247
cp "$P/u2wvideo-relay-status-v832.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 248
chmod 755 "$SHIM" "$LIB/u2w_mainvideo_relay" /etc/boa/cgi-bin/u2wvideo-relay-start.cgi /etc/boa/cgi-bin/u2wvideo-relay-stop.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 249
cat > /etc/u2w_v8_32_safe_checkpoint.marker <<MARKER
U2W MainVideo Safe Bounded Checkpoint Relay v8.32 (restored by v8.33 rollback)
base_mainvideo=v8.11_exact
base_selector_sha1=$V811_SHIM_SHA1
active_relay_sha1=$V832_RELAY_SHA1
MARKER
rm -f /etc/u2w_v8_33_lossless_mirror.marker
sync
log 'restored exact v8.11 mirror + v8.32 relay; normal updater reboot required; AppleCarPlay not signaled'
rm -f "$P/libu2w_mainvideo_live_v811.so" "$P/u2w_mainvideo_relay_v832" "$P/u2wvideo-relay-start-v832.cgi" "$P/u2wvideo-relay-stop-v832.cgi" "$P/u2wvideo-relay-status-v832.cgi" "$P/once.sh"
exit 0
