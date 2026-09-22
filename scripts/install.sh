#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/FloatingAgenda.app
if [ ! -d "$APP" ]; then
  echo "找不到 $APP，先執行 bash scripts/build.sh" >&2
  exit 1
fi

# 只檢查目錄存在不夠：建置若在組裝途中失敗，目錄會是個沒有執行檔或沒簽章的半成品，
# 裝上去之後才會在啟動時莫名其妙地失敗（codex 2026-09-22 指出）
if [ ! -x "$APP/Contents/MacOS/FloatingAgenda" ] || [ ! -f "$APP/Contents/Info.plist" ]; then
  echo "$APP 不完整（缺執行檔或 Info.plist），請重新執行 bash scripts/build.sh" >&2
  exit 1
fi
if ! codesign -v "$APP" 2>/dev/null; then
  echo "$APP 沒有有效簽章，請重新執行 bash scripts/build.sh" >&2
  exit 1
fi

DEST="$HOME/Applications"
mkdir -p "$DEST"

# 先關掉正在跑的舊版，否則複製過去也不會生效
if pgrep -x FloatingAgenda >/dev/null; then
  echo "關閉正在執行的 FloatingAgenda…"
  pkill -x FloatingAgenda || true
  sleep 1
fi

rm -rf "$DEST/FloatingAgenda.app"
cp -R "$APP" "$DEST/FloatingAgenda.app"
open "$DEST/FloatingAgenda.app"

echo "✅ installed to $DEST/FloatingAgenda.app（已啟動）"
