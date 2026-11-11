#!/bin/bash
# 跑全部测试：swift-testing、文案 key 校验、site 副本一致性。真删只发生在临时目录。
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swiftpm-env.sh
# CLT 的 _Testing_Foundation.framework 缺 Modules，关掉 cross-import overlay 才能同时 import Testing 和 Foundation
swift test ${SWIFT_TEST_FLAGS[@]+"${SWIFT_TEST_FLAGS[@]}"} -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
/usr/bin/python3 -I scripts/check_strings.py i18n/strings.json
for f in strings.json pebbles.js; do
  src=$([ "$f" = strings.json ] && echo i18n/$f || echo web/$f)
  cmp -s "$src" "site/$f" && echo "site/$f 与 $src 一致" || { echo "site/$f 过期，跑 scripts/sync-site.sh"; exit 1; }
done
[ "$(cat site/version.txt)" = "$(tr -d '[:space:]' < VERSION)" ] && echo "site/version.txt 与 VERSION 一致" || { echo "site/version.txt 过期"; exit 1; }
# 官网 index.html 里写死的 title、description、og 标签（给不跑脚本的抓取方看）必须和 strings.json 的 en 一致
/usr/bin/python3 -I -c '
import json,sys; en=json.load(open("i18n/strings.json",encoding="utf-8"))["en"]; h=open("site/index.html",encoding="utf-8").read()
need=["<title>%s</title>"%en["site.title"], "name=\"description\" content=\"%s\""%en["site.description"],
      "property=\"og:title\" content=\"%s\""%en["site.title"], "property=\"og:description\" content=\"%s\""%en["site.description"]]
bad=[n for n in need if n not in h]; [print("site/index.html 和 strings.json 不一致：" + b) for b in bad]
print("site/index.html 的 title、description、og 与 strings.json 一致") if not bad else sys.exit(1)'
bash scripts/test_install.sh
