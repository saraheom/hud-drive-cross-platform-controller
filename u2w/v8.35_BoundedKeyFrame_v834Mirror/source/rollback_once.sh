#!/bin/sh
set -u
VER=$(cat /etc/software_version 2>/dev/null); TYPE=$(cat /etc/box_product_type 2>/dev/null)
P=/tmp/update/tmp; LIB=/usr/lib/u2wvideo
V834_SHIM_SHA1=b982322ee65fd45405ab40f98512dbd76450976b
V831_RELAY_SHA1=b3964792342f9bc5ad22eaeb70eaf84ec04562f6
HELPER_SHA1=78859319b5cda7f8c42e7026b6f8502b3f7026f1
[ "$VER" = "2021.03.06.1343" ] && [ "$TYPE" = "U2W" ] || exit 271
[ -f /etc/u2w_v8_35_bounded_keyframe.marker ] || exit 272
[ -f "$P/u2wvideo-relay-status-v834.cgi" ] || exit 273
CUR_SHIM=$(sha1sum "$LIB/libu2w_mainvideo_live.so" 2>/dev/null | awk '{print $1}')
CUR_RELAY=$(sha1sum "$LIB/u2w_mainvideo_relay" 2>/dev/null | awk '{print $1}')
CUR_HELPER=$(sha1sum "$LIB/u2w_request_keyframe" 2>/dev/null | awk '{print $1}')
[ "$CUR_SHIM" = "$V834_SHIM_SHA1" ] || exit 274
[ "$CUR_RELAY" = "$V831_RELAY_SHA1" ] || exit 275
[ "$CUR_HELPER" = "$HELPER_SHA1" ] || exit 276
cp "$P/u2wvideo-relay-status-v834.cgi" /etc/boa/cgi-bin/u2wvideo-relay-status.cgi || exit 277
chmod 755 /etc/boa/cgi-bin/u2wvideo-relay-status.cgi
rm -f /etc/boa/cgi-bin/u2wvideo-request-keyframe.cgi "$LIB/u2w_request_keyframe"
rm -f /etc/u2w_v8_35_bounded_keyframe.marker /tmp/u2w_keyframe_last_epoch /tmp/u2w_keyframe_request_count /tmp/u2w_keyframe_request_status.txt
sync
rm -f "$P/u2wvideo-relay-status-v834.cgi" "$P/once.sh"
exit 0
