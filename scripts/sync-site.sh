#!/bin/bash
# 官网和 App 共用文案与卵石几何：把唯一来源复制到 site/
set -euo pipefail
cd "$(dirname "$0")/.."
cp i18n/strings.json site/strings.json
cp web/pebbles.js site/pebbles.js
tr -d '[:space:]' < VERSION > site/version.txt
[ -f .build/Rake.iconset/icon_256x256.png ] && cp .build/Rake.iconset/icon_256x256.png site/icon.png
echo "已同步 site/strings.json、site/pebbles.js、site/version.txt、site/icon.png"
