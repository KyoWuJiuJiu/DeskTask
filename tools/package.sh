#!/bin/bash
# 打包一个可分发的 zip（用于 GitHub Release）。
set -euo pipefail

cd "$(dirname "$0")/.."

./build.sh

VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
OUT="build/DeskTask-${VERSION}.zip"

rm -f "$OUT"
# ditto 会保留 bundle 的扩展属性与资源分叉，比 zip 命令更可靠
ditto -c -k --keepParent build/DeskTask.app "$OUT"

echo "已打包：$(pwd)/$OUT  ($(du -h "$OUT" | cut -f1))"
