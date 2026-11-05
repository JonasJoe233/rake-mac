# shellcheck shell=bash
# source 这个文件后用 "${SWIFT_FLAGS[@]}"：swift build "${SWIFT_FLAGS[@]}"。
# 只装了 Command Line Tools 26.2 的机器有两处坑，这里自动绕开；装了 Xcode 的机器（含 CI）两条都不触发。
#  1. usr/include/swift 下旧的 module.modulemap 和 bridging.modulemap 都定义 SwiftBridging，
#     编 Foundation 报 redefinition。用 VFS overlay 把旧的那份换成空文件。
#  2. ManifestAPI 里的 *.private.swiftinterface 是 2024 年的旧版，manifest 链接时找不到符号。
#     复制一份不带 private interface 的 ManifestAPI / PluginAPI，用 SWIFTPM_CUSTOM_LIBS_DIR 指过去。
# 另外 CLT 的 swift-testing 在 Library/Developer/Frameworks，不在默认搜索路径里，测试要加 -F 和 rpath。
SWIFT_FLAGS=()
_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_dev="$(xcode-select -p 2>/dev/null)"
if [ "$_dev" = "/Library/Developer/CommandLineTools" ]; then
  _fix="$_root/.build/clt-fix"
  _inc="$_dev/usr/include/swift"
  if [ -f "$_inc/module.modulemap" ] && [ -f "$_inc/bridging.modulemap" ] \
     && grep -q "module SwiftBridging" "$_inc/module.modulemap" && grep -q "module SwiftBridging" "$_inc/bridging.modulemap"; then
    mkdir -p "$_fix"; : > "$_fix/empty.modulemap"
    printf '{"version":0,"case-sensitive":"false","roots":[{"type":"directory","name":"%s","contents":[{"type":"file","name":"module.modulemap","external-contents":"%s"}]}]}\n' \
      "$_inc" "$_fix/empty.modulemap" > "$_fix/overlay.yaml"
    SWIFT_FLAGS+=(-Xswiftc -vfsoverlay -Xswiftc "$_fix/overlay.yaml")
  fi
  _pm="$_dev/usr/lib/swift/pm"
  if ls "$_pm/ManifestAPI/PackageDescription.swiftmodule/"*.private.swiftinterface >/dev/null 2>&1; then
    if [ ! -d "$_fix/pm/ManifestAPI" ]; then
      mkdir -p "$_fix/pm"; cp -R "$_pm/ManifestAPI" "$_pm/PluginAPI" "$_fix/pm/"
      find "$_fix/pm" -name "*.private.swiftinterface" -delete
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$_fix/pm"
  fi
  _fw="$_dev/Library/Developer/Frameworks"
  [ -d "$_fw/Testing.framework" ] && SWIFT_TEST_FLAGS=(-Xswiftc -F -Xswiftc "$_fw" -Xlinker -F -Xlinker "$_fw" -Xlinker -rpath -Xlinker "$_fw")
fi
SWIFT_TEST_FLAGS=("${SWIFT_FLAGS[@]}" "${SWIFT_TEST_FLAGS[@]}")
