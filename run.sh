#!/bin/bash
# 编译并重启。
#
# 两个坑：
# 1. 必须先杀掉正在跑的旧实例再 open —— 否则 LaunchServices 看到 bundle 已在运行，
#    只会去"激活"那个旧窗口（跑的还是旧代码），表现就是"重新构建后没有任何反应"。
# 2. 项目目录改名过（DeskMinder -> DeskTask），所以按可执行文件路径匹配而不是当前目录，
#    并且显式排除 /Applications/ —— 那是 App Store 装的正式版，绝不能杀。
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

killed=0
while read -r pid; do
  [ -z "$pid" ] && continue
  kill "$pid" 2>/dev/null && killed=1 || true
done < <(ps -Ao pid=,args= | awk '$0 ~ /Desk(Reminder|Minder|Task)\.app\/Contents\/MacOS\/Desk(Reminder|Minder|Task)$/ && $0 !~ /^ *[0-9]+ \/Applications\// { print $1 }')

[ "$killed" -eq 1 ] && { echo "已结束旧实例"; sleep 0.6; }

# 如果已经装到 /Applications，同步更新那一份，避免"启动台里还是旧版本"
if [ -d "/Applications/DeskTask.app" ]; then
  rm -rf "/Applications/DeskTask.app"
  ditto build/DeskTask.app "/Applications/DeskTask.app"
  xattr -cr "/Applications/DeskTask.app" 2>/dev/null || true
  codesign --force --sign - "/Applications/DeskTask.app" >/dev/null 2>&1 || true
  echo "已同步 /Applications/DeskTask.app"
  open "/Applications/DeskTask.app"
  echo "已启动：/Applications/DeskTask.app"
else
  open build/DeskTask.app
  echo "已启动：$(pwd)/build/DeskTask.app"
fi
