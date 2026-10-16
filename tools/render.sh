#!/bin/bash
# 把各个界面状态离屏渲染成 PNG，用来在不打开窗口的情况下检查观感与布局。
# 产物：/tmp/dm-*.png
set -euo pipefail

cd "$(dirname "$0")/.."

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -o /tmp/deskminder-render \
  Sources/Model.swift Sources/PullStops.swift Sources/PullBandView.swift Sources/PanelViews.swift \
  Sources/ChipView.swift Sources/WidgetView.swift Sources/WindowSupport.swift Sources/RemindersBridge.swift \
  tools/offscreen/main.swift \
  -framework Cocoa

/tmp/deskminder-render
echo
echo "产物：/tmp/dm-1-compact.png /tmp/dm-2-choosing.png /tmp/dm-3-stretching.png /tmp/dm-4-task.png /tmp/dm-5-list.png"
