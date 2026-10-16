#!/bin/bash
# 重新生成应用图标（Assets/AppIcon.icns）。
# 需要改配色/形状时改 tools/make-icon/main.swift 后跑这个。
set -euo pipefail

cd "$(dirname "$0")/.."

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -o /tmp/deskreminder-mkicon tools/make-icon/main.swift -framework Cocoa

WORK="$(mktemp -d)"
( cd "$WORK" && /tmp/deskreminder-mkicon )
cp "$WORK/AppIcon.icns" Assets/AppIcon.icns
rm -rf "$WORK"

echo "已更新：Assets/AppIcon.icns"
