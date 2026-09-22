#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/FloatingAgenda.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FloatingAgenda "$APP/Contents/MacOS/FloatingAgenda"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 可選：用自己的 bundle identifier 建置，例如
#   BUNDLE_ID=com.yourname.floatingagenda bash scripts/build.sh
# 只改建置產物，Resources/Info.plist 不動。換了 ID 等於換身分：
# 系統會重新詢問授權，UserDefaults 也會換 domain（設定回到預設值）。
if [[ -n "${BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
fi

# 沒有簽章憑證，只能 ad-hoc 簽章（PLAN §2、§9）
codesign --force --sign - --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature'

echo "✅ built $APP"
