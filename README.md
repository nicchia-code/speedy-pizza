# Speedy Reader

Flutter web MVP for fast reading.

Current scope:

- paste ebook text into the editor
- upload `.txt`, `.md`, `.html`, `.htm`, `.fb2`, `.epub` and `.pb` files in the browser
- show one word at a time
- highlight the central letter
- control speed in words per minute
- split `.pb` files by markers like `===== CAPITOLO 1 =====` into chapters
- save and restore last chapter and reading position from browser storage

Run locally:

```bash
HOME=/tmp XDG_CONFIG_HOME=/tmp DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true flutter run -d chrome
```

For mobile/LAN testing, prefer a release build served as static files instead of
`flutter run -d web-server` in debug mode:

```fish
./serve_web_lan.fish
```

This avoids Flutter's debug bootstrap/websocket flow, which can hang when the
page is opened from another device on the local network.
