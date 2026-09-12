# U2W v8.14.1 HUD Live Frame Relay Stability

This is the v8.14 relay with one important transport fix: KivicCast persistent UDP discovery on port 15320 remains alive for the entire relay session rather than closing after the first discovery reply. If the HUD briefly drops/reconnects, it can rediscover the MJPEG stream without restarting the U2W relay.

The U2W AP configuration is unchanged. Frame ingress remains TCP 15331 and MJPEG remains TCP 15330.
