#!/bin/bash
# 官网和 App 共用文案与卵石几何：把唯一来源复制到 site/
set -euo pipefail
cd "$(dirname "$0")/.."
cp i18n/strings.json site/strings.json
cp web/pebbles.js site/pebbles.js
echo "已同步 site/strings.json、site/pebbles.js"
