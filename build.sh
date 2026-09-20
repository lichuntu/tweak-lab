#!/bin/bash
# 在 macOS 上编译 MinTweak.dylib（本地跑 / GitHub Actions 跑都可以）
set -euo pipefail

OUT=build
mkdir -p "$OUT"

# 选最新的 Xcode（GitHub runner 上常装了多个版本）
if [ -d /Applications ]; then
  newest=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)
  if [ -n "${newest:-}" ] && [ -d "$newest/Contents/Developer" ]; then
    echo "使用 Xcode: $newest"
    (sudo xcode-select -s "$newest" 2>/dev/null) || (xcode-select -s "$newest" 2>/dev/null) || true
  fi
fi

echo "--- 环境 ---"
xcode-select -p || true
xcodebuild -version || true
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK 路径: $SDK"
echo -n "SDK 版本: "; xcrun --sdk iphoneos --show-sdk-version || true

NAME=MinTweak
ARCH=arm64
MIN_IOS=15.0

echo "--- 编译 ---"
xcrun --sdk iphoneos clang \
  -arch "$ARCH" \
  -miphoneos-version-min="$MIN_IOS" \
  -isysroot "$SDK" \
  -dynamiclib \
  -fobjc-arc \
  -O2 \
  -Wl,-undefined,dynamic_lookup \
  -install_name "@executable_path/$NAME.dylib" \
  -framework Foundation \
  -framework UIKit \
  -o "$OUT/$NAME.dylib" \
  src/Tweak.m

echo "--- 产物 ---"
ls -l "$OUT"
lipo -info "$OUT/$NAME.dylib" || true
echo "--- 依赖 ---"
otool -L "$OUT/$NAME.dylib" || true
echo "--- 最低系统版本 ---"
xcrun vtool -show-build "$OUT/$NAME.dylib" || true
