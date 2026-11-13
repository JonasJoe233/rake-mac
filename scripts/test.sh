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
# App 界面的 G()（web/app.html）和引擎的 fmtSize 用同一套规则：1000 进制，不到 1 GB 显示 MB
if command -v node >/dev/null; then
  node -e '
const src=require("fs").readFileSync("web/app.html","utf8"), line=src.split("\n").find(l=>l.startsWith("const G="));
const G=eval(line.slice(8).replace(/;$/,""));
const want=[[0.999,"999 MB"],[1,"1.0 GB"],[16.858,"17 GB"],[0,"0 MB"],[0.0006,"1 MB"],[0.9996,"1.0 GB"],[9.94,"9.9 GB"],[10,"10 GB"]];
const bad=want.filter(([v,w])=>G(v)!==w); bad.forEach(([v,w])=>console.log("web/app.html G("+v+") = "+G(v)+"，应为 "+w));
if(bad.length) process.exit(1); console.log("web/app.html 的大小格式与引擎一致（"+want.length+" 个样例）");'
else echo "跳过 web/app.html 大小格式检查：没有 node"; fi
bash scripts/test_install.sh
