#!/bin/sh
printf 'Content-Type: text/plain\r\nCache-Control: no-store\r\n'
MARK=/etc/u2w_v8_35_bounded_keyframe.marker
HELPER=/usr/lib/u2wvideo/u2w_request_keyframe
LAST=/tmp/u2w_keyframe_last_epoch
COUNT=/tmp/u2w_keyframe_request_count
STATE=/tmp/u2w_keyframe_request_status.txt
COOLDOWN=8
if [ ! -f "$MARK" ] || [ ! -x "$HELPER" ]; then
  printf 'Status: 503 Service Unavailable\r\n\r\n'
  echo 'result=not_installed'
  exit 0
fi
NOW=$(date +%s 2>/dev/null || echo 0)
PREV=0; [ -f "$LAST" ] && PREV=$(cat "$LAST" 2>/dev/null || echo 0)
case "$PREV" in ''|*[!0-9]*) PREV=0;; esac
case "$NOW" in ''|*[!0-9]*) NOW=0;; esac
if [ "$NOW" -gt 0 ] && [ "$PREV" -gt 0 ]; then
  DELTA=$((NOW-PREV))
  if [ "$DELTA" -lt "$COOLDOWN" ]; then
    printf 'Status: 429 Too Many Requests\r\n\r\n'
    echo 'result=rate_limited'
    echo "cooldown_seconds=$COOLDOWN"
    echo "elapsed_seconds=$DELTA"
    exit 0
  fi
fi
printf '%s\n' "$NOW" > "$LAST"
"$HELPER"
RC=$?
N=0; [ -f "$COUNT" ] && N=$(cat "$COUNT" 2>/dev/null || echo 0)
case "$N" in ''|*[!0-9]*) N=0;; esac
N=$((N+1)); printf '%s\n' "$N" > "$COUNT"
case "$RC" in
  0) RESULT=sent; ROUTE=adb-driver; HTTP='200 OK' ;;
  10) RESULT=sent; ROUTE=phonemirror-fallback; HTTP='200 OK' ;;
  *) RESULT=send_failed; ROUTE=none; HTTP='503 Service Unavailable' ;;
esac
cat > "$STATE" <<STATE
last_epoch=$NOW
request_count=$N
result=$RESULT
route=$ROUTE
helper_exit=$RC
header_magic=0x55AA55AA
header_type=0x0C
payload_bytes=0
STATE
printf 'Status: %s\r\n\r\n' "$HTTP"
echo 'version=v8.35-bounded-keyframe-request'
echo "result=$RESULT"
echo "route=$ROUTE"
echo "request_count=$N"
echo "helper_exit=$RC"
echo 'request_type=0x0C'
echo 'payload_bytes=0'
echo 'process_restart=NO'
echo 'process_signal=NO'
echo 'tcp_reconnect=NO'
exit 0
