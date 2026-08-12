# Media and navigation sources

Physical iPhone testing established that the accessory notification path works
for normal Notification Center events (for example Messages and KakaoTalk).

Spotify current-track metadata and live turn-by-turn map guidance did not appear
through that path.

The app therefore treats the following as separate source classes:

- ANCS notifications: Messages, calls, mail, social/messaging notifications.
- Media / Now Playing: future accessory/media metadata path.
- Navigation: manual simulator today; future Google/Apple/Waze/visual provider.

This keeps the working notification pipeline separate from future media and
navigation integrations.
