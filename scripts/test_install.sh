#!/bin/bash
# install.sh 测试：用本地 build/Rake.dmg，不联网，不碰 /Applications。
set -uo pipefail
cd "$(dirname "$0")/.."
[ -f build/Rake.dmg ] || { echo "install.sh 测试跳过：没有 build/Rake.dmg（先跑 build.sh 和 dmg.sh）"; exit 0; }
BASE=$(mktemp -d "${TMPDIR:-/tmp}/rake-install-test.XXXX")
trap 'chmod -R u+w "$BASE" 2>/dev/null; rm -rf "$BASE"' EXIT
URL="file://$PWD/build/Rake.dmg"
FAIL=0
# 1. RAKE_DEST 指向事先不存在的目录：应建目录并装进去
DEST="$BASE/not-yet/apps"
RAKE_DMG_URL="$URL" RAKE_DEST="$DEST" bash install.sh >"$BASE/log1" 2>&1; rc=$?
if [ $rc -eq 0 ] && [ -x "$DEST/Rake.app/Contents/MacOS/Rake" ]; then echo "通过 install.sh 装进不存在的 RAKE_DEST"; else echo "失败 install.sh 装进不存在的 RAKE_DEST（退出 ${rc}）"; cat "$BASE/log1"; FAIL=1; fi
# 2. RAKE_DEST 写不进：应非 0 退出，且没有装到别处
mkdir -p "$BASE/ro"; chmod 555 "$BASE/ro"
RAKE_DMG_URL="$URL" RAKE_DEST="$BASE/ro/apps" bash install.sh >"$BASE/log2" 2>&1; rc=$?
if [ $rc -ne 0 ] && [ ! -e "$BASE/ro/apps" ] && ! grep -q "Installed to" "$BASE/log2"; then echo "通过 install.sh 写不进 RAKE_DEST 时报错退出（退出 ${rc}）"; else echo "失败 install.sh 写不进 RAKE_DEST（退出 ${rc}）"; cat "$BASE/log2"; FAIL=1; fi
exit $FAIL
