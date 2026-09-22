#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/FloatingAgenda.app
if [ ! -d "$APP" ]; then
  echo "找不到 $APP，先執行 bash scripts/build.sh" >&2
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
