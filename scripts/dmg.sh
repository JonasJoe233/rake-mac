#!/bin/bash
# 用系统自带 hdiutil 把 build/Rake.app 打成 build/Rake.dmg（文件名固定，官网链接靠它）。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Rake.app; DMG=build/Rake.dmg
test -d "$APP" || { echo "先跑 scripts/build.sh"; exit 1; }
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/rake-dmg.XXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Rake" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "校验通过"
ls -lh "$DMG" | awk '{print $5, $9}'
shasum -a 256 "$DMG"
