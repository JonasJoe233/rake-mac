#!/bin/bash
# 编 universal Rake.app：arm64 和 x86_64 各编一次（CLT 没有 xcbuild，不能一次 --arch 两个），lipo 合成，ad-hoc 签名。
# 产物：build/Rake.app
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swiftpm-env.sh
VERSION=$(tr -d '[:space:]' < VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/Rake.app
for arch in arm64 x86_64; do
  echo "== 编 $arch"
  swift build -c release --arch "$arch" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --product Rake 2>&1 | grep -E "error|warning: |Compiling|Build complete" || true
  test -x ".build/$arch-apple-macosx/release/Rake" || { echo "$arch 编译失败"; exit 1; }
done
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Rake" .build/arm64-apple-macosx/release/Rake .build/x86_64-apple-macosx/release/Rake
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" packaging/Info.plist > "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/web" "$APP/Contents/Resources/i18n"
cp web/app.html web/pebbles.js "$APP/Contents/Resources/web/"
cp i18n/strings.json "$APP/Contents/Resources/i18n/"
cp LICENSE NOTICE VERSION "$APP/Contents/Resources/"
ICONSET=.build/Rake.iconset
if [ ! -f .build/Rake.icns ] || [ packaging/make_icon.swift -nt .build/Rake.icns ]; then
  ICON_FLAGS=(); for f in ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}; do [ "$f" != "-Xswiftc" ] && ICON_FLAGS+=("$f"); done  # 去掉 -Xswiftc 前缀给 swiftc 直接用
  rm -rf "$ICONSET"; swiftc ${ICON_FLAGS[@]+"${ICON_FLAGS[@]}"} packaging/make_icon.swift -o .build/make_icon
  .build/make_icon "$ICONSET" && iconutil -c icns "$ICONSET" -o .build/Rake.icns
fi
cp .build/Rake.icns "$APP/Contents/Resources/Rake.icns"
codesign --force --deep -s - "$APP"
echo "== 结果"
lipo -archs "$APP/Contents/MacOS/Rake"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature"
du -sh "$APP"
