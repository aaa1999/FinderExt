#!/bin/bash
# FinderExt 一键构建 + 安装脚本
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> 编译 Release"
xcodebuild -project FinderExt.xcodeproj \
  -scheme FinderExt \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build

APP="build/DerivedData/Build/Products/Release/FinderExt.app"
if [ ! -d "$APP" ]; then
  echo "构建产物不存在: $APP" >&2
  exit 1
fi

echo "==> 停止旧进程"
pkill -x FinderExt 2>/dev/null || true
sleep 1

echo "==> 安装到 /Applications"
rm -rf "/Applications/FinderExt.app"
cp -R "$APP" "/Applications/"

echo "==> 启动 FinderExt"
open -a /Applications/FinderExt.app
sleep 2

echo "==> 尝试启用 Finder 扩展"
pluginkit -e use -i com.lwc.finderext.extension 2>/dev/null || true

echo ""
echo "✅ 安装完成。"
echo "   请确认：系统设置 → 通用 → 登录项与扩展 → 扩展 → Finder 扩展 中 FinderExt 已开启，"
echo "   然后在 Finder 任意文件夹内右键测试「在此打开终端」「新建文件…」。"
