#!/bin/bash
# 把 DeskReminder 装成"正式应用"：
#   1. 复制到 /Applications —— 这样才会出现在启动台(Launchpad)和聚焦搜索里
#   2. 装一个 LaunchAgent —— 开机/登录后自动启动
#
# 用法：
#   ./install.sh              安装（含开机自启）
#   ./install.sh --no-login   只装进 /Applications，不设开机自启
#   ./install.sh --uninstall  卸载（同时移除开机自启）
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DeskReminder"
TARGET="/Applications/${APP_NAME}.app"
LABEL="local.deskreminder.login"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BIN="/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
DOMAIN="gui/$(id -u)"

uninstall() {
  echo "==> 移除开机自启"
  launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
  rm -f "$PLIST"
  ps -Ao pid=,args= | awk '$0 ~ /\/Applications\/DeskReminder\.app\/Contents\/MacOS\/DeskReminder$/ { print $1 }' \
    | while read -r pid; do kill "$pid" 2>/dev/null || true; done
  sleep 0.6
  echo "==> 移除 /Applications/${APP_NAME}.app"
  rm -rf "$TARGET"
  echo "已卸载。"
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

./build.sh

# 顺序很重要：必须先把旧实例和旧 job 停掉，再替换 app 目录。
# 否则会一边删掉正在运行的可执行文件、一边让 launchd 去拉一个已经不存在的路径，
# 结果是 bootstrap 报 "Input/output error"，登录项反而丢了。
echo "==> 停掉旧实例与旧 job"
launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
ps -Ao pid=,args= | awk '$0 ~ /\/Applications\/DeskReminder\.app\/Contents\/MacOS\/DeskReminder$/ { print $1 }' \
  | while read -r pid; do kill "$pid" 2>/dev/null || true; done
sleep 0.8

echo "==> 复制到 ${TARGET}"
# ditto 会连扩展属性和资源分叉一起正确复制；先删掉旧的避免残留
rm -rf "$TARGET"
ditto "build/${APP_NAME}.app" "$TARGET"
xattr -cr "$TARGET" 2>/dev/null || true
codesign --force --sign - "$TARGET" >/dev/null 2>&1 || true

if [ "${1:-}" = "--no-login" ]; then
  echo "==> 跳过开机自启（--no-login）"
  echo "完成。现在可以从启动台打开「${APP_NAME}」。"
  exit 0
fi

echo "==> 安装开机自启（LaunchAgent）"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <!-- 只在这个用户的图形登录会话里跑，不要在 ssh / 后台上下文里也起一个 -->
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST_EOF

# bootout 是异步的，紧接着 bootstrap 可能撞上 "already bootstrapped / Input/output error"，重试几轮
for attempt in 1 2 3 4; do
  if launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then
    break
  fi
  if [ "$attempt" = "4" ]; then
    echo "warning: launchctl bootstrap 一直失败；可稍后手动执行 launchctl bootstrap ${DOMAIN} ${PLIST}"
  fi
  sleep 1
done

echo
echo "完成。"
echo "  · 启动台里现在能找到「${APP_NAME}」"
echo "  · 下次登录会自动启动"
echo "  · 关闭自启：./install.sh --uninstall"
