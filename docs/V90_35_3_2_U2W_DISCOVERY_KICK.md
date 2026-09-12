# v90.35.3.2 — U2W relay post-association discovery kick

Observed field state:

- HUD reported STA status 1 and address `192.168.50.100`.
- iPhone frame ingress remained connected and continued sending JPEG frames.
- U2W v8.14.1 status showed all three daemons running and a nonzero latest frame.
- U2W discovery log showed only `persistent-discovery-listening-15320`: no HUD discovery packet and no MJPEG client.
- Repeated full Start/Stop cycles later produced status 6 / `Empty network`, because Stop cleared the saved STA credentials and those asynchronous status events could bleed into the next attempt.

Fix:

1. Treat STA `status=1` as the synchronization point.
2. Re-prime `IOS_KIVICCAST_STA_MODE(6)` after association/DHCP so the KivicCast viewer performs discovery on the established interface.
3. Query U2W status for `hud_mjpeg_established=YES`; if absent, perform one bounded mode-6 retry.
4. Disable repeated full Start while the relay is already active; expose a dedicated **Retry HUD display** action instead.
5. Stop no longer erases STA credentials.
6. Pair with U2W v8.14.2, where `u2whud-start.cgi` reuses healthy daemons instead of restarting the relay stack.
