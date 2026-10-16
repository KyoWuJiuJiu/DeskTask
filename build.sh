#!/bin/bash
# 编译并组装 DeskMinder.app（只需要 Command Line Tools，不需要 Xcode）
set -euo pipefail

cd "$(dirname "$0")"

APP="build/DeskReminder.app"
BIN="$APP/Contents/MacOS/DeskReminder"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -o "$BIN" \
  Sources/*.swift \
  -framework Cocoa

cp Info.plist "$APP/Contents/Info.plist"

if [ -f Assets/AppIcon.icns ]; then
  cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: 缺少 Assets/AppIcon.icns（可用 ./tools/make-icon.sh 生成），将使用系统默认图标"
fi

# swiftc 产出的二进制自带 ad-hoc 签名；但要给 bundle 重新签名，必须先清掉扩展属性。
# 这个目录在 iCloud Drive 下，fileprovider 会把 com.apple.FinderInfo 异步加回来，
# 所以清一次可能白清，这里重试几轮。
signed=0
for _ in 1 2 3 4 5; do
  xattr -cr "$APP"
  if codesign --force --sign - "$APP" >/dev/null 2>&1; then
    signed=1
    break
  fi
  sleep 0.5
done

if [ "$signed" -eq 1 ]; then
  echo "signed: ad-hoc"
else
  echo "warning: ad-hoc 签名没成功；二进制本身已带链接器签名，本机运行通常不受影响"
fi

echo "built: $(pwd)/$APP"
