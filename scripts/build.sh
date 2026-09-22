#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/FloatingAgenda.app
rm -rf "$APP"
# 中途失敗就把半成品清掉，避免 install.sh 把沒組好的 .app 裝上去
trap 'rm -rf "$APP"' ERR
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FloatingAgenda "$APP/Contents/MacOS/FloatingAgenda"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 可選：用自己的 bundle identifier 建置，例如
#   BUNDLE_ID=com.yourname.floatingagenda bash scripts/build.sh
# 只改建置產物，Resources/Info.plist 不動。換了 ID 等於換身分：
# 系統會重新詢問授權，UserDefaults 也會換 domain（設定回到預設值）。
if [[ -n "${BUNDLE_ID:-}" ]]; then
  # 先驗格式再寫入。PlistBuddy 對含空白或奇怪字元的值會解析失敗，
  # 而那時 .app 目錄已經建好了——install.sh 只檢查目錄存在，
  # 會把這個沒簽好的半成品裝上去（codex 2026-09-22 指出）
  if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
    echo "BUNDLE_ID 格式不正確：$BUNDLE_ID" >&2
    echo "要用反向 DNS 形式，只能有英數、連字號與點，例如 com.yourname.floatingagenda" >&2
    rm -rf "$APP"
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
fi

# 沒有簽章憑證，只能 ad-hoc 簽章（PLAN §2、§9）
codesign --force --sign - --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature'

trap - ERR
echo "✅ built $APP"
