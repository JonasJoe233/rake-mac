#!/bin/bash
# Rake 安装脚本：curl -fsSL https://raw.githubusercontent.com/JonasJoe233/rake-mac/main/install.sh | bash
#
# 做了什么：从 GitHub Releases 下载最新的 Rake.dmg，挂载，把 Rake.app 复制到 /Applications，卸载 dmg，删掉临时文件。
# 不用 sudo。/Applications 不可写时改装到 ~/Applications。
# 设了 RAKE_DEST 就只装到那里：目录不存在先建，建不了或写不进就报错退出，不退回别的位置。
#
# 关于 Gatekeeper：浏览器下载的文件会被打上 com.apple.quarantine 隔离标记，首次打开未公证的 App 时 macOS 会拦。
# curl 下载的文件不带这个标记，所以用这种方式装的 Rake 不会弹 Gatekeeper 提示。脚本本身不去掉任何标记，也不改系统设置。
set -euo pipefail
URL="${RAKE_DMG_URL:-https://github.com/JonasJoe233/rake-mac/releases/latest/download/Rake.dmg}"
if [ -n "${RAKE_DEST:-}" ]; then
  DEST="$RAKE_DEST"
  mkdir -p "$DEST" 2>/dev/null && [ -w "$DEST" ] || { echo "无法写入 / Cannot write to $DEST" >&2; exit 1; }
elif [ -w /Applications ]; then
  DEST=/Applications
else
  DEST="$HOME/Applications"; mkdir -p "$DEST"
fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/rake-install.XXXX")
MNT="$TMP/mnt"
cleanup() { hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
echo "下载 / Downloading $URL"
curl -fL --progress-bar "$URL" -o "$TMP/Rake.dmg"
mkdir -p "$MNT"
hdiutil attach "$TMP/Rake.dmg" -nobrowse -readonly -mountpoint "$MNT" -quiet
test -d "$MNT/Rake.app" || { echo "dmg 里没有 Rake.app"; exit 1; }
if pgrep -xq Rake; then echo "Rake 正在运行，请先退出 / Quit Rake first"; exit 1; fi
rm -rf "$DEST/Rake.app"
ditto "$MNT/Rake.app" "$DEST/Rake.app"
echo "已安装到 / Installed to $DEST/Rake.app"
echo "打开 / Open: open \"$DEST/Rake.app\""
