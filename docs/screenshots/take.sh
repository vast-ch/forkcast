#!/usr/bin/env bash
# Retake the README screenshots from production with the dev container's
# Chromium, then shrink them to JPEG (macOS sips). Run from the repo root.
set -euo pipefail
site=https://forkcast.vast.earth
out=docs/screenshots
tmp=$(mktemp -d)

shot() { # name scale window-size url
  docker compose exec -T ui chromium --headless=new --no-sandbox --hide-scrollbars \
    --force-device-scale-factor="$2" --window-size="$3" --virtual-time-budget=25000 \
    --screenshot="/tmp/$1.png" "$4" >/dev/null 2>&1
  docker compose cp "ui:/tmp/$1.png" "$tmp/$1.png" >/dev/null 2>&1
}

shot desktop 2 1440,900 "$site/?start=2026-10-25&day=12&week=41"
shot route 2 1440,900 "$site/?route=ev6&start=2027-05-15&km=100&day=20&week=21"
shot phone 3 390,844 "$site/?start=2027-04-10&day=8&week=15"

for f in desktop route; do
  sips -Z 1800 -s format jpeg -s formatOptions 75 "$tmp/$f.png" --out "$out/$f.jpg" >/dev/null
done
sips -Z 1300 -s format jpeg -s formatOptions 75 "$tmp/phone.png" --out "$out/phone.jpg" >/dev/null
