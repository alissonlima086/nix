#!/usr/bin/env bash

notify-send "yt-play" "Script executado"

url="${1:-$(wl-paste -n 2>/dev/null)}"

if [[ "$url" =~ ^https?://(www\.)?(youtube\.com|youtu\.be)/ ]]; then
  mpv --ytdl-raw-options=cookies-from-browser=firefox "$url" >/dev/null 2>&1 &
fi
```

