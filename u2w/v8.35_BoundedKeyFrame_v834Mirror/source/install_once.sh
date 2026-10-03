#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null)
TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp
LIB=/usr/lib/u2wvideo
SHIM=$LIB/libu2w_mainvideo_live.so
RELAY=$LIB/u2w_mainvideo_relay
MARK=/etc/u2w_v8_35_bounded_keyframe.marker
V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
HELPER_SHA1=78859319b5cda7f8c42e7026b6f8502b3f7026f1
log(){ echo "[U2W-v8.35] $*" > /dev/console; }
if [ "$VER" != "2021.03.06.1343" ] || [ "$TYPE" != "U2W" ]; then log "ABORT version/type $TYPE/$VER"; exit 251; fi
[ -f /etc/u2w_v8_34_hard_bounded_mirror.marker ] || { log 'ABORT v8.34 hard-bounded mirror baseline missing'; exit 252; }
for f in u2w_request_keyframe u2wvideo-request-keyframe.cgi u2wvideo-relay-status.cgi; do [ -f "$P/$f" ] || { log "ABORT payload missing $f"; exit 253; }; done
CUR_SHIM=$(sha1sum "$SHIM" 2>/dev/null | awk '{print $1}')
CUR_RELAY=$(sha1sum "$RELAY" 2>/dev/null | awk '{print $1}')
[ "$CUR_SHIM" = "$V834_SHIM_SHA1" ] || { log "ABORT expected exact v8.34 shim got $CUR_SHIM"; exit 254; }
[ "$CUR_RELAY" = "$V831_RELAY_SHA1" ] || { log "ABORT expected exact v8.31 raw relay got $CUR_RELAY"; exit 255; }
PAYLOAD_HELPER=$(sha1sum "$P/u2w_request_keyframe" 2>/dev/null | awk '{print $1}')
[ "$PAYLOAD_HELPER" = "$HELPER_SHA1" ] || { log "ABORT keyframe helper hash $PAYLOAD_HELPER"; exit 256; }
# Incremental safety boundary: do not stop, signal, replace, or restart any
# CarPlay/MainVideo process. v8.34 mirror + exact v8.31 relay stay byte-identical.
cp "$P/u2w_request_keyframe" "$LIB/u2w_request_keyframe" || exit 257
cp "$P/u2wvideo-request-keyframe.cgi" /etc/boa/cgi-bin/u2wvideo-request-keyframe.cgi || exit 258
cp "$P/u2wvideo-relay-status.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 259
chmod 755 "$LIB/u2w_request_keyframe" /etc/boa/cgi-bin/u2wvideo-request-keyframe.cgi /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 260
rm -f /tmp/u2w_keyframe_last_epoch /tmp/u2w_keyframe_request_count /tmp/u2w_keyframe_request_status.txt
cat > "$MARK" <<MARKER
U2W v8.35 Bounded RequestKeyFrame helper over unchanged v8.34 mirror/raw relay
software_version=$VER
product_type=$TYPE
active_v834_shim_sha1=$V834_SHIM_SHA1
active_v831_raw_relay_sha1=$V831_RELAY_SHA1
keyframe_helper_sha1=$HELPER_SHA1
request_header_magic=0x55AA55AA
request_header_type=0x0C
request_payload_bytes=0
request_routes=/var/run/adb-driver,/var/run/phonemirror-single-fallback
adapter_cooldown_seconds=8
applecarplay_payload_modified=0
applecarplay_signal_policy=NEVER
applecarplay_restart_policy=NEVER
armiphoneiap2_signal_policy=NEVER
armiphoneiap2_restart_policy=NEVER
mainvideo_tcp_reconnect_policy=NEVER_BY_KEYFRAME_HELPER
mirror_changed=0
raw_relay_changed=0
route_guidance_changed=0
now_playing_changed=0
MARKER
sync
log 'installed v8.35 bounded keyframe helper; v8.34 mirror + v8.31 raw relay unchanged; no process signal/restart'
rm -f "$P/u2w_request_keyframe" "$P/u2wvideo-request-keyframe.cgi" "$P/u2wvideo-relay-status.cgi" "$P/once.sh"
exit 0
